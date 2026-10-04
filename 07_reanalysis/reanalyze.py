"""Independent re-analysis of CityPulse Study 1 traces (read-only copy of the team's data).
Evaluates every configuration's chosen route under ONE common reference belief (the C3 fused
p_mean at the replay clock), instead of each configuration's own p_tilde. Also re-runs a
z/lambda sweep with a scipy re-implementation of the documented edge cost, validated against
the Dart router's own C3 traces."""
import json, sys, math, random
from pathlib import Path
from collections import defaultdict
import numpy as np
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import dijkstra

ROOT = Path(__file__).resolve().parents[1] / '01_code' / 'citypulse-IDP'
sys.path.insert(0, str(ROOT / 'scripts'))
import t3_2_replay_engine as t32
import study_common as sc

WORK = Path(__file__).parent
at = t32.parse_iso8601(t32.REPLAY_CLOCK)
hz = t32.load_hazard_classes()
obs_by_edge = t32.load_corpus()
prior = {}
for line in open(WORK / 'prior_sub.txt'):
    e, lo, p = line.split(); prior[int(e)] = {'prior_logodds': float(lo), 'prior_p': float(p)}
configs, stats = t32.build_hazard_configs(obs_by_edge, prior, hz)
rel = hz['source_reliability']
pmean = {}; neff = {}; sev = {}
for eid, c in configs.items():
    obs = sc.with_reliability(c.observations, rel)
    f = sc.fuse_py(obs, c.prior_logodds, at, c.decay_tau_seconds)
    pmean[eid] = f['p_mean']; neff[eid] = f['n_eff']; sev[eid] = c.severity
print('hazard-config edges', len(configs), stats['edges_with_real_observations'])

g = json.load(open(ROOT / 'data/graph/2026-09-14/chennai_graph_cli.json'))
E = g['edges']; N = g['node_count']
src = np.array([e['from'] for e in E]); dst = np.array([e['to'] for e in E])
tau = np.array([e['free_flow_seconds'] for e in E]); eid_arr = np.array([e['edge_id'] for e in E])
pm = np.zeros(len(E)); ne = np.zeros(len(E)); sv = np.zeros(len(E)); has = np.zeros(len(E), bool)
idx_of = {int(x): i for i, x in enumerate(eid_arr)}
for eid in configs:
    i = idx_of[eid]; pm[i] = pmean[eid]; ne[i] = neff[eid]; sv[i] = sev[eid]; has[i] = True
# best edge per (u,v) by free-flow (for mapping node paths to edges)
pair = {}
for i in range(len(E)):
    k = (int(src[i]), int(dst[i]))
    if k not in pair or tau[i] < tau[pair[k]]: pair[k] = i

def path_edges(nodes, weight=None):
    out = []
    for u, v in zip(nodes, nodes[1:]):
        out.append(pair[(u, v)])
    return out

def exposure(eidx):
    p = pm[eidx]; t = tau[eidx]
    return dict(worst_p=float(p.max()) if len(p) else 0.0,
                tw_mean_p=float((p * t).sum() / t.sum()) if t.sum() > 0 else 0.0,
                exp_hazard_edges=float(p.sum()),
                t_highrisk_s=float(t[p >= 0.5].sum()),
                n_highrisk=int((p >= 0.5).sum()),
                ff_s=float(t.sum()))

def load_traces(name):
    out = []
    for line in open(ROOT / f'data/results/2026-09-18-study1-route-quality/traces/{name}.ndjson'):
        tr = json.loads(line)
        nodes = [int(x) for x in tr['chosen']['geometry_ref'].split(':', 1)[1].split(',')]
        out.append((tr['query_id'], nodes, tr))
    return out

res = {}
tr = {c: load_traces(c) for c in ['C0', 'C1', 'C3']}
for c in tr:
    res[c] = [exposure(np.array(path_edges(n))) for _, n, _ in tr[c]]
ods = [(n[0], n[-1]) for _, n, _ in tr['C0']]

def summ(vals):
    a = np.array(vals); return dict(mean=float(a.mean()), p50=float(np.percentile(a, 50)), p90=float(np.percentile(a, 90)), max=float(a.max()))

def boot_ci(diffs, B=5000, seed=20261001):
    rng = np.random.default_rng(seed); d = np.array(diffs)
    m = [rng.choice(d, len(d)).mean() for _ in range(B)]
    return [float(np.percentile(m, 2.5)), float(np.percentile(m, 97.5))]

out = {'reference_belief': 'C3 fused p_mean at replay clock 2015-12-02T00:00:00Z (z-independent), identical for every configuration', 'n_od': len(ods)}
for c in ['C0', 'C1', 'C3']:
    out[c] = {k: summ([r[k] for r in res[c]]) for k in res[c][0]}
for c in ['C1', 'C3']:
    d = {}
    for k in ['worst_p', 'tw_mean_p', 'exp_hazard_edges', 't_highrisk_s', 'ff_s']:
        diffs = [res[c][i][k] - res['C0'][i][k] for i in range(len(ods))]
        d[k] = dict(mean_diff=float(np.mean(diffs)), ci95=boot_ci(diffs))
    d['n_pairs_route_changed'] = int(sum(1 for i in range(len(ods)) if tr[c][i][1] != tr['C0'][i][1]))
    d['share_pairs_highrisk_C0'] = float(np.mean([res['C0'][i]['n_highrisk'] > 0 for i in range(len(ods))]))
    d['share_pairs_highrisk_cfg'] = float(np.mean([res[c][i]['n_highrisk'] > 0 for i in range(len(ods))]))
    out[f'{c}_minus_C0'] = d

# ---- scipy re-implementation of the documented cost, validated vs Dart C3 traces ----
def pess(z):
    band = z * np.sqrt(pm * (1 - pm) / (ne + 1)); return np.minimum(pm + band, 1.0)

def solve(z, lam, pairs):
    w = tau.copy()
    pt = pess(z)
    w[has] = tau[has] * (1 + lam * pt[has] * sv[has])
    M = csr_matrix((w, (src, dst)), shape=(N, N))  # duplicates summed! handle below
    return w

# handle parallel edges: keep min weight per (u,v)
order = defaultdict(list)
def build(w):
    best = {}
    for i in range(len(E)):
        k = (int(src[i]), int(dst[i]))
        if k not in best or w[i] < w[best[k]]: best[k] = i
    ii = np.array(list(best.values()))
    return csr_matrix((w[ii], (src[ii], dst[ii])), shape=(N, N)), {k: v for k, v in best.items()}

def route(M, bestmap, s, t):
    d, pred = dijkstra(M, directed=True, indices=s, return_predecessors=True, limit=np.inf)
    if not np.isfinite(d[t]): return None
    nodes = [t]
    while nodes[-1] != s: nodes.append(int(pred[nodes[-1]]))
    nodes.reverse()
    return nodes, [bestmap[(u, v)] for u, v in zip(nodes, nodes[1:])]

def weights(z, lam):
    w = tau.copy(); pt = pess(z)
    w[has] = tau[has] * (1 + lam * pt[has] * sv[has]); return w

# validation: C3 z=0 lambda=0.3 on all 100 OD pairs
M, bm = build(weights(0.0, 0.3))
match = 0; cost_ok = 0
w03 = weights(0.0, 0.3)
for i, (s, t) in enumerate(ods):
    r = route(M, bm, s, t)
    dart_nodes = tr['C3'][i][1]
    if r[0] == dart_nodes: match += 1
    dart_cost = sum(w03[pair2] for pair2 in path_edges(dart_nodes))
    my_cost = sum(w03[j] for j in r[1])
    if abs(dart_cost - my_cost) <= 1e-6 * max(1, dart_cost) + 1e-6: cost_ok += 1
out['validation_vs_dart_C3'] = {'identical_node_paths': match, 'equal_optimal_cost': cost_ok, 'n': len(ods)}

# corrected Pareto sweep on all 100 OD pairs, exposure under common reference p_mean
sweep = []
Mff, bmff = build(tau.copy())
ff_routes = [route(Mff, bmff, s, t) for s, t in ods]
for z in [0.0, 0.5, 1.0, 1.28, 2.0]:
    for lam in [0.3, 1.0, 2.0, 5.0, 10.0, 20.0]:
        M, bm = build(weights(z, lam))
        det, hr, twp, dh, eh = [], [], [], [], []
        for (s, t), ff in zip(ods, ff_routes):
            r = route(M, bm, s, t)
            e = exposure(np.array(r[1])); e0 = exposure(np.array(ff[1]))
            det.append(e['ff_s'] / e0['ff_s']); hr.append(e['n_highrisk'] > 0); twp.append(e['tw_mean_p']); dh.append(e['t_highrisk_s']); eh.append(e['exp_hazard_edges'])
        sweep.append(dict(z=z, lam=lam, median_detour=float(np.median(det)), p90_detour=float(np.percentile(det, 90)),
                          share_routes_touching_pbar_ge_0_5=float(np.mean(hr)), mean_tw_pbar=float(np.mean(twp)), mean_highrisk_seconds=float(np.mean(dh)), mean_detour=float(np.mean(det)), mean_exp_hazard_edges=float(np.mean(eh))))
        print(sweep[-1], flush=True)
e0s = [exposure(np.array(ff[1])) for ff in ff_routes]
out['freeflow_reference'] = dict(share_routes_touching_pbar_ge_0_5=float(np.mean([e['n_highrisk'] > 0 for e in e0s])), mean_tw_pbar=float(np.mean([e['tw_mean_p'] for e in e0s])), mean_highrisk_seconds=float(np.mean([e['t_highrisk_s'] for e in e0s])))
out['pareto_common_reference'] = sweep
# ALT-consistency empirical check: hazard weights >= free-flow on every edge for every config
out['min_weight_ratio_over_sweep'] = float(min((weights(z, l) / tau).min() for z in [0, 2.0] for l in [0.3, 5.0]))
# belief summary
p_obs = np.array([pmean[e] for e in configs if configs[e].observations]); p_pri = np.array([pmean[e] for e in configs if not configs[e].observations])
out['belief_summary'] = dict(n_edges_obs=int(len(p_obs)), pbar_obs_p50=float(np.median(p_obs)), pbar_obs_share_ge_0_5=float((p_obs >= 0.5).mean()), n_edges_prior_only=int(len(p_pri)), pbar_prior_p50=float(np.median(p_pri)))
json.dump(out, open(WORK / 'reanalysis_result.json', 'w'), indent=1)
print(json.dumps({k: v for k, v in out.items() if k != 'pareto_common_reference'}, indent=1))
