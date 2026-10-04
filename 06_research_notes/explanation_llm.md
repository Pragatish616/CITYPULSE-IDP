# Route explanation, LLMs for mobility/disaster, verified data-to-text, and on-device small LMs (2019–2026)

Scope: prior art for CityPulse AI's explanation stack: deterministic template (Tier 0), then a small-LM or cloud-LM rewrite (Tier 1/2) that is shown only if a symbolic verifier passes (numerals, entities, comparatives, data-gap coherence, confidence hedge, no absolute-safety claims), with the template as the fail-closed fallback. All 45 entries below are NEW: none appear in /home/claude/citypulse_context/refs.tsv (checked against its 129 keys). Works already in refs.tsv are not repeated: koo2015car, reiter1997nlg, vandeemter2005template, dusek2020e2e, osuji2024d2t, ji2023hallucination, min2023factscore, manakul2023selfcheck, honovich2022true, kryscinski2020factcc, willard2023guided, gao2023alce, xiao2024pockets, li2024palmbench, liu2024mobilellm, gemma2025gemma3, abdin2024phi3, xu2024ondevice, turpin2023unfaithful, jacovi2020faithful, miller2019explanation.

How metadata was checked: Bash had no network (proxy 403 for arxiv.org, export.arxiv.org and api.crossref.org), so every record was opened through the Exa fetch tool, either on the arXiv abstract page or on the Crossref REST API (`api.crossref.org/works?filter=doi:…` or `query.bibliographic=…`, with a `select` for title, author, container, page and published). VERIFIED means the title, authors in order, venue and year were read from that primary record during this session. Caveats are marked in the table.

---

## Verified reference table

| # | Proposed key | Authors (in order) | Exact title | Venue, vol(issue), pages | Year | DOI / arXiv | Status |
|---|---|---|---|---|---|---|---|
| 1 | alsheeb2023explainable | Khalid Alsheeb; Martim Brandão | Towards Explainable Road Navigation Systems | 2023 IEEE 26th Int. Conf. on Intelligent Transportation Systems (ITSC), 16–22 | 2023 | 10.1109/ITSC57777.2023.10422542 | VERIFIED (Crossref) |
| 2 | brandao2021pathplan | Martim Brandão; Amanda Coles; Daniele Magazzeni | Explaining Path Plan Optimality: Fast Explanation Methods for Navigation Meshes Using Full and Incremental Inverse Optimization | Proc. ICAPS 31(1), 56–64 | 2021 | 10.1609/icaps.v31i1.15947 | VERIFIED (Crossref) |
| 3 | schild2025route | Aaron Schild; Sreenivas Gollapudi; Anupam Gupta; Kostas Kollias; Ali Sinop | Why is My Route Different Today? An Algorithm for Explaining Route Selection | Proc. SIAM Conf. on Applied and Computational Discrete Algorithms (ACDA), 251–263 | 2025 | 10.1137/1.9781611978759.19; arXiv:2506.05604 | VERIFIED (Crossref + arXiv) |
| 4 | kikuta2024routeexplainer | Daisuke Kikuta; Hiroki Ikeuchi; Kengo Tajiri; Yuusuke Nakano | RouteExplainer: An Explanation Framework for Vehicle Routing Problem | PAKDD 2024, LNCS (Advances in Knowledge Discovery and Data Mining), 30–42 | 2024 | 10.1007/978-981-97-2259-4_3; arXiv:2403.03585 | VERIFIED (Crossref + arXiv) |
| 5 | vredenborg2026tone | Marloes Vredenborg; Marit Bentvelzen; Christine Bauer; Judith Masthoff | Does Tone Matter? Exploring Context-Aware Explanations in Route Recommendations | Proc. 34th ACM UMAP, 30–39 | 2026 | 10.1145/3774935.3806780 | VERIFIED (Crossref) |
| 6 | ilyankou2026scenic | Ilya Ilyankou; Stefano Cavazzi; James Haworth | The Scenic Route to Deception: Dark Patterns and Explainability Pitfalls in Conversational Navigation | arXiv preprint (cs.HC) | 2026 | arXiv:2603.14586 | VERIFIED (arXiv) |
| 7 | moratz2025bilateral | R. Moratz; N. Daute; J. Ondieki; M. Kattenbeck; M. Krajina; I. Giannopoulos | Bilateral Spatial Reasoning about Street Networks: Graph-based RAG with Qualitative Spatial Representations | arXiv preprint (cs.AI) | 2025 | arXiv:2512.15388 | VERIFIED (arXiv; authors as initials from the arXiv HTML) |
| 8 | hallgarten2025routellm | Philipp Hallgarten; Verena Jasmin Hallitschke; Enkelejda Kasneci; Michael Beigl; Tobias Grosse-Puppendahl | RouteLLM: A Large Language Model with Native Route Context Understanding to Enable Context-Aware Reasoning | Proc. ACM IMWUT 9(3), 1–34 | 2025 | 10.1145/3749552 | VERIFIED (Crossref) |
| 9 | braun2025pave | Carnot Braun; Rafael O. Jarczewski; Gabriel U. Talasso; Leandro A. Villas; Allan M. de Souza | Beyond Shortest Path: Agentic Vehicular Routing with Semantic Context | UrbanAI workshop paper; arXiv preprint | 2025 | arXiv:2511.04464 | VERIFIED (arXiv); host conference of the workshop not confirmed |
| 10 | thill2018adherence | Serge Thill; Maria Riveiro; Erik Lagerstedt; Mikael Lebram; Paul Hemeren; Azra Habibovic; Maria Klingegård | Driver adherence to recommendations from support systems improves if the systems explain why they are given: A simulator study | Transportation Research Part F 56, 420–435 | 2018 | 10.1016/j.trf.2018.05.009 | VERIFIED (Crossref) |
| 11 | samson2019connected | Briane Paul V. Samson; Yasuyuki Sumi | Exploring Factors that Influence Connected Drivers to (Not) Use or Follow Recommended Optimal Routes | Proc. CHI 2019, 1–14 | 2019 | 10.1145/3290605.3300601 | VERIFIED (Crossref) |
| 12 | lei2025disaster | Zhenyu Lei; Yushun Dong; Weiyu Li; Rong Ding; Qi R. Wang; Jundong Li | Harnessing Large Language Models for Disaster Management: A Survey | Findings of ACL 2025, 14528–14551 | 2025 | 10.18653/v1/2025.findings-acl.750; arXiv:2501.06932 | VERIFIED (Crossref + arXiv) |
| 13 | xu2025disasterreview | Fengyi Xu; Jun Ma; Nan Li; Jack C.P. Cheng | Large language model applications in disaster management: An interdisciplinary review | Int. J. Disaster Risk Reduction 127, 105642 | 2025 | 10.1016/j.ijdrr.2025.105642 | VERIFIED (Crossref) |
| 14 | zhu2025urbandisaster | Guishui Zhu; Feifei Zhang; Rajiv Ranjan; Schahram Dustdar; Jiabao Li; Yiyue Wang; Yuewei Wang; Xiaohui Huang; Yunliang Chen; L. Wang | A Survey of Large Language Models in Urban Natural Disaster Emergency Management: Progress, Application, and Challenges | IEEE Internet Computing 29(4), 66–76 | 2025 | 10.1109/MIC.2025.3566787 | VERIFIED (Crossref for the first 9 authors, issue and year; the pages and the 10th author "Wang, L." come from the TU Wien repository record) |
| 15 | goecks2023disastergpt | Vinicius G. Goecks; Nicholas R. Waytowich | DisasterResponseGPT: Large Language Models for Accelerated Plan of Action Development in Disaster Response Scenarios | ICML 2023 Workshop on Challenges in Deployable Generative AI; arXiv | 2023 | arXiv:2306.17271 | VERIFIED (arXiv) |
| 16 | colverd2023floodbrain | Grace Colverd; Paul Darm; Leonard Silverberg; Noah Kasmanoff | FloodBrain: Flood Disaster Reporting by Web-based Retrieval Augmented Generation with an LLM | arXiv preprint | 2023 | arXiv:2311.02597 | VERIFIED (arXiv) |
| 17 | otal2024crisis | Hakan T. Otal; Eric Stern; M. Abdullah Canbaz | LLM-Assisted Crisis Management: Building Advanced LLM Platforms for Effective Emergency Response and Public Collaboration | 2024 IEEE Conf. on Artificial Intelligence (CAI), 851–859 | 2024 | 10.1109/CAI59869.2024.00159 | VERIFIED (Crossref) |
| 18 | wandelt2024its | Sebastian Wandelt; Changhong Zheng; Shuang Wang; Yucheng Liu; Xiaoqian Sun | Large Language Models for Intelligent Transportation: A Review of the State of the Art and Challenges | Applied Sciences 14(17), 7455 | 2024 | 10.3390/app14177455 | VERIFIED (Crossref) |
| 19 | nie2025llm4tr | Tong Nie; Jian Sun; Wei Ma | Exploring the Roles of Large Language Models in Reshaping Transportation Systems: A Survey, Framework, and Roadmap | arXiv preprint | 2025 | arXiv:2503.21411 | VERIFIED (arXiv) |
| 20 | yan2025llmtransport | Yimo Yan; Yejia Liao; Guanhao Xu; Ruili Yao; Huiying Fan; Jingran Sun; Xia Wang; Jonathan Sprinkle; Ziyan An; Meiyi Ma; Xi Cheng; Tong Liu; Zemian Ke; Bo Zou; Matthew Barth; Yong-Hong Kuo | Large Language Models for Traffic and Transportation Research: Methodologies, State of the Art, and Future Opportunities | arXiv preprint | 2025 | arXiv:2503.21330 | VERIFIED (arXiv) |
| 21 | zhang2024trafficgpt | Siyao Zhang; Daocheng Fu; Wenzhe Liang; Zhao Zhang; Bin Yu; Pinlong Cai; Baozhen Yao | TrafficGPT: Viewing, processing and interacting with traffic foundation models | Transport Policy 150, 95–105 | 2024 | 10.1016/j.tranpol.2024.03.006; arXiv:2309.06719 | VERIFIED (Crossref) |
| 22 | zhang2024mobilityllm | Zijian Zhang; Yujie Sun; Zepu Wang; Yuqi Nie; Xiaobo Ma; et al. (running header: "Zhang, Sun, Wang, Nie, Ma, Li, Sun and Ban") | Large Language Models for Mobility Analysis in Transportation Systems: A Survey on Forecasting Tasks | arXiv preprint (TRB-format manuscript) | 2024 | arXiv:2405.02357 | VERIFIED (arXiv); full given names after the 5th author not read |
| 23 | kale2020t2g2 | Mihir Kale; Abhinav Rastogi | Template Guided Text Generation for Task-Oriented Dialogue | Proc. EMNLP 2020, 6505–6520 | 2020 | 10.18653/v1/2020.emnlp-main.527; arXiv:2004.15006 | VERIFIED (Crossref) |
| 24 | harkous2020datatuner | Hamza Harkous; Isabel Groves; Amir Saffari | Have Your Text and Use It Too! End-to-End Neural Data-to-Text Generation with Semantic Fidelity | Proc. COLING 2020, 2410–2424 | 2020 | 10.18653/v1/2020.coling-main.218; arXiv:2004.06577 | VERIFIED (Crossref) |
| 25 | dusek2020nli | Ondřej Dušek; Zdeněk Kasner | Evaluating Semantic Accuracy of Data-to-Text Generation with Natural Language Inference | Proc. INLG 2020, 131–137 | 2020 | 10.18653/v1/2020.inlg-1.19; arXiv:2011.10819 | VERIFIED (Crossref) |
| 26 | thomson2020gold | Craig Thomson; Ehud Reiter | A Gold Standard Methodology for Evaluating Accuracy in Data-To-Text Systems | Proc. INLG 2020, 158–168 | 2020 | 10.18653/v1/2020.inlg-1.22; arXiv:2011.03992 | VERIFIED (Crossref) |
| 27 | kasner2021textincontext | Zdeněk Kasner; Simon Mille; Ondřej Dušek | Text-in-Context: Token-Level Error Detection for Table-to-Text Generation | Proc. INLG 2021, 259–265 | 2021 | 10.18653/v1/2021.inlg-1.25 | VERIFIED (Crossref) |
| 28 | rebuffel2022controlling | Clement Rebuffel; Marco Roberti; Laure Soulier; Geoffrey Scoutheeten; Rossella Cancelliere; Patrick Gallinari | Controlling hallucinations at word level in data-to-text generation | Data Mining and Knowledge Discovery 36, 318–354 | 2022 (online 22 Oct 2021) | 10.1007/s10618-021-00801-4; arXiv:2102.02810 | VERIFIED (Crossref) |
| 29 | balakrishnan2019constrained | Anusha Balakrishnan; Jinfeng Rao; Kartikeya Upasani; Michael White; Rajen Subba | Constrained Decoding for Neural NLG from Compositional Representations in Task-Oriented Dialogue | Proc. ACL 2019, 831–844 | 2019 | 10.18653/v1/P19-1080; arXiv:1906.07220 | VERIFIED (Crossref) |
| 30 | kasner2024quintd | Zdeněk Kasner; Ondřej Dušek | Beyond Traditional Benchmarks: Analyzing Behaviors of Open LLMs on Data-to-Text Generation | Proc. ACL 2024 (Vol. 1: Long), 12045–12072 | 2024 | 10.18653/v1/2024.acl-long.651; arXiv:2401.10186 | VERIFIED (Crossref) |
| 31 | thomson2023views | Craig Thomson; Clement Rebuffel; Ehud Reiter; Laure Soulier; Somayajulu Sripada; Patrick Gallinari | Enhancing factualness and controllability of Data-to-Text Generation via data Views and constraints | Proc. INLG 2023, 221–236 | 2023 | 10.18653/v1/2023.inlg-main.16 | VERIFIED (Crossref + ACL Anthology) |
| 32 | ren2025vcp | Xuan Ren; Zeyu Zhang; Lingqiao Liu | You Can Generate It Again: Data-to-Text Generation with Verification and Correction Prompting | Proc. 7th ACM Int. Conf. on Multimedia in Asia (MMAsia), 1–10 | 2025 | 10.1145/3743093.3771022; arXiv:2306.15933 | VERIFIED (Crossref) |
| 33 | geng2023gcd | Saibo Geng; Martin Josifoski; Maxime Peyrard; Robert West | Grammar-Constrained Decoding for Structured NLP Tasks without Finetuning | Proc. EMNLP 2023, 10932–10952 | 2023 | 10.18653/v1/2023.emnlp-main.674; arXiv:2305.13971 | VERIFIED (Crossref) |
| 34 | maynez2020faithfulness | Joshua Maynez; Shashi Narayan; Bernd Bohnet; Ryan McDonald | On Faithfulness and Factuality in Abstractive Summarization | Proc. ACL 2020 (ACL Anthology 2020.acl-main.173) | 2020 | 10.18653/v1/2020.acl-main.173 (from the Anthology ID); arXiv:2005.00661 | VERIFIED (arXiv); pages not read; the DOI is inferred from the Anthology ID and was not confirmed in Crossref |
| 35 | tang2024minicheck | Liyan Tang; Philippe Laban; Greg Durrett | MiniCheck: Efficient Fact-Checking of LLMs on Grounding Documents | Proc. EMNLP 2024, 8818–8847 | 2024 | 10.18653/v1/2024.emnlp-main.499; arXiv:2404.10774 | VERIFIED (Crossref) |
| 36 | bao2025faithbench | Forrest Sheng Bao; Miaoran Li; Renyi Qu; Ge Luo; Erana Wan; Yujia Tang; Weisi Fan; Manveer Singh Tamber; Suleman Kazi; Vivek Sourabh; Mike Qi; Ruixuan Tu; Chenyu Xu; Matthew Gonzales; Ofer Mendelevitch; Amin Ahmad | FaithBench: A Diverse Hallucination Benchmark for Summarization by Modern LLMs | Proc. NAACL 2025 (Short), DOI 2025.naacl-short.38 | 2025 | 10.18653/v1/2025.naacl-short.38; arXiv:2410.13210 | VERIFIED (Crossref + arXiv); pages not read |
| 37 | pan2023programfc | Liangming Pan; Xiaobao Wu; Xinyuan Lu; Anh Tuan Luu; William Yang Wang; Min-Yen Kan; Preslav Nakov | Fact-Checking Complex Claims with Program-Guided Reasoning | Proc. ACL 2023 (Vol. 1: Long), 6981–7004 | 2023 | 10.18653/v1/2023.acl-long.386; arXiv:2305.12744 | VERIFIED (Crossref) |
| 38 | laskaridis2024melt | Stefanos Laskaridis; Kleomenis Katevas; Lorenzo Minto; Hamed Haddadi | MELTing Point: Mobile Evaluation of Language Transformers | Proc. 30th ACM MobiCom, 890–907 | 2024 | 10.1145/3636534.3690668; arXiv:2403.12844 | VERIFIED (Crossref) |
| 39 | murthy2024mobileaibench | Rithesh Murthy; Liangwei Yang; Juntao Tan; Tulika Manoj Awalgaonkar; Yilun Zhou; Shelby Heinecke; Sachin Desai; Jason Wu; Ran Xu; Sarah Tan; Jianguo Zhang; Zhiwei Liu; Shirley Kokane; Zuxin Liu; Ming Zhu; Huan Wang; Caiming Xiong; Silvio Savarese | MobileAIBench: Benchmarking LLMs and LMMs for On-Device Use Cases | arXiv preprint | 2024 | arXiv:2406.10290 | VERIFIED (arXiv) |
| 40 | lu2024slmsurvey | Zhenyan Lu; Xiang Li; Dongqi Cai; Rongjie Yi; Fangming Liu; Xiwen Zhang; Nicholas D. Lane; Mengwei Xu | Small Language Models: Survey, Measurements, and Insights | arXiv preprint | 2024 | arXiv:2409.15790 | VERIFIED (arXiv) |
| 41 | lu2025demystifying | Zhenyan Lu; Xiang Li; Dongqi Cai; Rongjie Yi; Fangming Liu; Wei Liu; Jian Luan; Xiwen Zhang; Nicholas D. Lane; Mengwei Xu | Demystifying Small Language Models for Edge Deployment | Proc. ACL 2025 (Vol. 1: Long), 14747–14764 | 2025 | 10.18653/v1/2025.acl-long.718 | VERIFIED (Crossref + ACL Anthology) |
| 42 | xu2025llmnpu | Daliang Xu; Hao Zhang; Liming Yang; Ruiqi Liu; Gang Huang; Mengwei Xu; Xuanzhe Liu | Fast On-device LLM Inference with NPUs | Proc. ASPLOS '25, Vol. 1, 445–462 | 2025 | 10.1145/3669940.3707239; arXiv:2407.05858 | VERIFIED (Crossref) |
| 43 | allal2025smollm2 | Loubna Ben Allal; Anton Lozhkov; Elie Bakouch; Gabriel Martín Blázquez; Guilherme Penedo; Lewis Tunstall; Andrés Marafioti; Hynek Kydlíček; Agustín Piqueres Lajarín; Vaibhav Srivastav; Joshua Lochner; Caleb Fahlgren; Xuan-Son Nguyen; Clémentine Fourrier; Ben Burtenshaw; Hugo Larcher; Haojun Zhao; Cyril Zakka; Mathieu Morlon; Colin Raffel; Leandro von Werra; Thomas Wolf | SmolLM2: When Smol Goes Big — Data-Centric Training of a Small Language Model | arXiv preprint | 2025 | arXiv:2502.02737 | VERIFIED (arXiv) |
| 44 | guegain2026battery | Édouard Guégain; Tristan Coignion | The Battery Price of edge AI: A study of the Environmental Impact of LLM Inference on Mobile Devices | arXiv preprint (cs.PF) | 2026 | arXiv:2609.11940 | VERIFIED (arXiv page), but CAUTION: the page says "Submitted on 10 Jul 2026" while the ID prefix 2609 means September 2026. Re-check before citing |
| 45 | hariharan2026mobibench | Arya Hariharan; Rohit Suresh; Bolla Sai Naga Yashwanth; Ashok Senapati; Thummala Pallavi; Anala M R; Soumya A | MobiBench: Benchmarking LLMs for On-Device Performance | arXiv preprint (cs.PF) | 2026 | arXiv:2609.13159 | VERIFIED (arXiv page), but CAUTION: same date/ID mismatch ("Submitted on 15 Jul 2026", ID 2609). The runtime name is elided as "this http URL" in the abstract |

Leads seen but NOT verified (do not cite as they stand): Dale, Geldof & Prost (2005), NLG for automatic route description; "Mitigating Geospatial Knowledge Hallucination in Large Language Models" (Findings of EMNLP 2025, aclanthology.org/2025.findings-emnlp.45); "Probing post-hoc reasoning in LLMs over multi-step pathfinding tasks" (venue unknown); MulSAFER, a safety-aware routing framework with interpretable output (2025; venue unknown); Lerouge et al., "Modeling and generating user-centered contrastive explanations for the workforce scheduling and routing problem" (journal not confirmed); Wang (2020), a Leibniz Universität Hannover student thesis on explanations in a navigation app (grey literature, 20 participants).

---

## Q1. Who has explained route choices in natural language, before and during the LLM era?

### Takeaway
Route-choice explanation is a small, recent line of work. Its algorithmic core is contrastive and counterfactual: inverse optimisation, minimal sets of congested segments, and edge-influence models. Generating the wording is either left out or handed to GPT-4, and none of the works checks that the generated text is faithful to the algorithm's output. HCI evidence shows that explanations raise adherence to route recommendations and that explanation tone should depend on context.

### Cited Findings
- **Alsheeb & Brandão (ITSC 2023)** combine inverse optimisation with diverse-shortest-path algorithms to give "optimal explanations" to two questions: "why is path A fastest, rather than path B (which the user provides)?" and "why does the fastest path not go through waypoint W?". The explanations reveal map properties (speed limits, congestion, road closures) that conflict with the user's expectations. The authors demonstrate this on real map and traffic data and evaluate the algorithms' properties; the abstract reports no user study and no NL-faithfulness metric. — [Exa library record](https://exa.ai/library/publication/vtrhyn6jd7r); [Crossref](https://api.crossref.org/works?query.bibliographic=Towards+Explainable+Road+Navigation+Systems+Alsheeb+Brandao&rows=2)
- **Brandão, Coles & Magazzeni (ICAPS 2021)** is the predecessor: fast explanations of path-plan optimality on navigation meshes using full and incremental inverse optimisation. — [Crossref](https://api.crossref.org/works?query.bibliographic=Explaining+path+plan+optimality+fast+explanation+methods+for+navigation+meshes+inverse+optimization+Brandao&rows=1)
- **Schild, Gollapudi, Gupta, Kollias & Sinop (Google Research/NYU; ACDA 2025)** define a "simple valid explanation" (SVE): a small set of traffic-laden road segments that answers "which traffic conditions cause a particular shortest traffic-aware route to differ from the shortest traffic-free route?" They give an efficient algorithm and show that the answers are small and interpretable, both theoretically and experimentally. Code is in google-research/explainable_routing. The output is a set of segments, not generated text. — [arXiv:2506.05604](https://arxiv.org/abs/2506.05604v2); [Crossref](https://api.crossref.org/works?query.bibliographic=Why+is+My+Route+Different+Today+Explaining+Route+Selection+Schild+Gollapudi&rows=1)
- **RouteExplainer (Kikuta et al., PAKDD 2024)** is a post-hoc, solver-agnostic counterfactual explanation framework for VRP. It extends the action influence model to an "Edge Influence Model", adds an edge-intention classifier, and generates the explanation text with an LLM (GPT-4, per the repo). The edge classifier is evaluated quantitatively on four VRPs; the generated explanations are evaluated only qualitatively, on a tourist-route case. — [arXiv:2403.03585](https://arxiv.org/abs/2403.03585); [GitHub](https://github.com/ntt-dkiku/route-explainer); [Exa search highlights](https://arxiv.org/html/2403.03585)
- **Vredenborg, Bentvelzen, Bauer & Masthoff (UMAP 2026)** study whether the tone of explanations for public-transport route recommendations should depend on the user's situational context, arguing that multimodal journey planning yields many plausible route permutations that travellers must weigh quickly. — [Crossref](https://api.crossref.org/works?filter=doi:10.1145/3774935.3806780); [ACM DL](https://dlnext.acm.org/doi/10.1145/3774935.3806780)
- **Thill et al. (TRF 2018)** ran a driving-simulator study with 123 participants covering eco-driving and navigation support. Conditions were no support, basic (icon) support, and informative support (icon plus a line of justifying text). Per the title, adherence improves when the system explains why a recommendation is given. — [Crossref](https://api.crossref.org/works?query.bibliographic=Driver+adherence+to+recommendations+from+support+systems+improves+if+the+systems+explain+why+they+are+given&rows=1); [ScienceDirect abstract](https://www.sciencedirect.com/science/article/pii/S1369847816300286)
- **Samson & Sumi (CHI 2019)** ran a qualitative study of 17 drivers, mostly from the Philippines and Japan. Drivers follow recommended routes mainly in urgent situations, which challenges the assumption that drivers always want the fastest route. — [ACM DL](https://dl.acm.org/doi/10.1145/3290605.3300601); [Crossref](https://api.crossref.org/works/10.1145/3290605.3300601)
- **LLM-era route reasoning without explanation-faithfulness checks:**
  - RouteLLM (Hallgarten et al., IMWUT 2025) converts route series into tokens with a VQ-VAE and fine-tunes Mistral-7B-Instruct, so the model can answer route-context questions such as "Is this a scenic route?". — [PDF](https://www.grosse-puppendahl.com/publications/imwut2025.pdf); [Crossref](https://api.crossref.org/works?query.bibliographic=RouteLLM+Large+Language+Model+with+Native+Route+Context+Understanding+Hallgarten&rows=1)
  - PAVe (Braun et al., 2025) has an LLM agent choose among candidate routes produced by a multi-objective (time, CO2) Dijkstra, using a pre-processed POI cache. It reports ">88% accuracy in its initial route selections with a local model". — [arXiv:2511.04464](https://arxiv.org/abs/2511.04464)
- **LLM route instructions hallucinate street names.** Moratz et al. (2025) show ChatGPT-4o inventing a non-existent street ("Willy-Brandt-Allee" in Münster) and giving disconnected turn sequences for a pedestrian route. They test graph-based RAG with qualitative spatial relations as a mitigation. — [arXiv HTML 2512.15388](https://arxiv.org/html/2512.15388)
- **Ilyankou, Cavazzi & Haworth (2026)** argue that LLM-based pedestrian navigation risks turning routing "from a verifiable geometric task into an opaque, persuasive dialogue". They give a 2×2 taxonomy (dark patterns vs. explainability pitfalls) and propose "neuro-symbolic architecture, where verifiable pathfinding algorithms ground GenAI's persuasive capabilities". The paper is conceptual; the abstract reports no implementation or metric. — [arXiv:2603.14586](https://arxiv.org/abs/2603.14586)

### Inferences
- Every route-explanation system we found produces an explanation object (inverse-optimisation deltas, SVE segment sets, edge influences). Only RouteExplainer verbalises it with an LLM, and none of them checks that the verbalisation matches the object. That check is CityPulse's Tier-1/2 verifier, so the most defensible novelty claim sits at the interface between explanation object and text, not in the explanation algorithm.
- Schild et al.'s SVE is the closest analogue to a hazard-aware "why is my route different" explanation. The CityPulse DecisionTrace could be framed as an SVE-like minimal set of hazard-penalised edges, and this paper should be cited as the algorithmic baseline for "why this route".

### Gaps
- No paper found explains a route choice made under hazard or flood uncertainty, or under a pessimistic or chance-constrained cost (as opposed to traffic).
- No route-explanation paper found reports a text-faithfulness metric, for example the share of explanations whose numerals or road names match the solver output.
- The pre-LLM NLG route-description literature (e.g., Dale, Geldof & Prost 2005) was not re-verified in this pass.

---

## Q2. LLMs for transport, urban mobility and disaster response: surveys and key systems

### Takeaway
Several 2024–2026 surveys exist for both transport and disaster. All of them name hallucination as a central risk, and in disaster settings the stated harm is "false evacuation routes". The mitigations they report are RAG, domain fine-tuning and uncertainty estimation. Programmatic or symbolic verification of generated guidance against structured routing data is absent.

### Cited Findings
- **Lei et al. (Findings of ACL 2025)** give a taxonomy across mitigation, preparedness, response and recovery. Under "Robust Generation" they state that LLM hallucination "pose[s] serious risks in disaster contexts, such as false evacuation routes, resource misallocation, and potential loss of lives". Proposed mitigations are RAG (citing FloodBrain), domain-specific training and uncertainty estimation. Under "Efficient Deployment" they note that lightweight models "often compromise robustness in disaster-related tasks". For evacuation planning, LLMs have been prompted to generate escape plans (Hostetter et al., 2024). — [ACL Anthology PDF](https://aclanthology.org/2025.findings-acl.750.pdf); [arXiv:2501.06932](https://arxiv.org/pdf/2501.06932v2.pdf)
- **Xu, Ma, Li & Cheng (IJDRR 2025)** analyse 70 LLM-focused disaster studies and identify gaps, including the "inadequate transformation of situation awareness data into actionable insights". They propose a "3M" framework (multi-modal fusion, multi-source information validation, multi-agent collaboration). — [Exa library record](https://exa.ai/library/publication/j35z8l4kyp9); [Crossref](https://api.crossref.org/works?query.bibliographic=Large+language+model+applications+in+disaster+management+An+interdisciplinary+review+Xu+Ma+Li+Cheng&rows=2)
- **Zhu et al. (IEEE Internet Computing 2025)** survey LLMs in urban natural-disaster emergency management before, during and after disasters, and propose an application framework and technical route. — [TU Wien repository](https://repositum.tuwien.at/handle/20.500.12708/229330?mode=full); [Crossref](https://api.crossref.org/works?filter=doi:10.1109/MIC.2025.3566787)
- **FloodBrain (Colverd et al., 2023)** uses web-based RAG for flood impact reports and explicitly targets hallucination. — [arXiv:2311.02597](https://arxiv.org/abs/2311.02597)
- **DisasterResponseGPT (Goecks & Waytowich, ICML 2023 workshop)** puts planning guidelines in the prompt to generate plans of action. Its preliminary results are "comparable to human-generated ones"; no automatic faithfulness check is described. — [arXiv:2306.17271](https://arxiv.org/abs/2306.17271v2)
- **Otal, Stern & Canbaz (IEEE CAI 2024)** describe LLM platforms for emergency response and public collaboration. — [Crossref](https://api.crossref.org/works?filter=doi:10.1109/cai59869.2024.00159)
- **Transport surveys:**
  - Wandelt et al. (Applied Sciences 2024) review more than 130 papers across autonomous driving, safety, tourism, traffic and other areas. — [MDPI](https://www.mdpi.com/2076-3417/14/17/7455)
  - Nie, Sun & Ma (2025) propose the LLM4TR framework of LLM roles in transportation. — [arXiv:2503.21411](https://arxiv.org/abs/2503.21411)
  - Yan et al. (2025) cover methodologies from 2023–2025. — [arXiv:2503.21330](https://arxiv.org/abs/2503.21330)
  - Zhang et al. (2024) survey LLMs for mobility forecasting. — [arXiv:2405.02357](https://arxiv.org/abs/2405.02357)
- **TrafficGPT (Zhang et al., Transport Policy 2024)** states that "LLMs struggle with addressing traffic issues, especially processing numerical data and interacting with simulations". It couples an LLM with specialised traffic foundation models (tool use) instead of letting the LLM compute. — [arXiv:2309.06719](https://arxiv.org/abs/2309.06719); [Crossref](https://api.crossref.org/works?query.bibliographic=TrafficGPT+Viewing+Processing+and+Interacting+with+Traffic+Foundation+Models&rows=2)

### Inferences
- The disaster surveys name exactly the failure CityPulse guards against (hallucinated evacuation or route content) but list only soft mitigations. A fail-closed symbolic verifier answers that stated challenge directly and can be positioned that way, citing Lei et al. 2025.
- TrafficGPT's observation that LLMs handle numbers poorly supports CityPulse's design choice to keep all numbers in the deterministic trace and to treat the LM as a paraphraser only.

### Gaps
- No LLM-for-disaster paper found reports a quantitative hallucination rate for generated evacuation or route guidance.
- I did not find an India- or Chennai-specific LLM flood-guidance study in this pass.

---

## Q3. What symbolic or programmatic verification of generated text against structured data exists?

### Takeaway
Before LLMs, data-to-text (D2T) NLG already had the CityPulse ingredients: template-then-rewrite (T2G2), overgenerate-and-rerank with a semantic-fidelity classifier (DataTuner), slot-error-rate regex checkers, rule-based keyword verification with regeneration (VCP), constrained decoding over structured meaning representations, and grammar-constrained decoding. What is missing in this literature is a deterministic, typed verifier (numerals, entities, comparatives, hedges, safety claims) that gates display and falls back to the template, rather than reranking or regenerating.

### Cited Findings
- **T2G2 (Kale & Rastogi, EMNLP 2020)** is the closest architectural ancestor. Simple per-action templates are concatenated into a "semantically correct, but possibly incoherent and ungrammatical utterance", and a pre-trained LM (T5) "is subsequently employed to rewrite it into coherent, natural sounding text". It improves over baselines and generalises zero-shot to unseen domains (+7.3 BLEU over the naive representation on unseen domains). Human evaluation used 500 examples with 3 raters each, rating informativeness and naturalness on a 1–3 scale. There is no runtime verifier: faithfulness is assessed only offline. — [ACL Anthology](https://aclanthology.org/2020.emnlp-main.527/); [ar5iv](https://ar5iv.labs.arxiv.org/html/2004.15006)
- **DataTuner (Harkous, Groves & Saffari, COLING 2020)** is a two-stage generate-and-rerank system: a fine-tuned LM plus a learned semantic-fidelity classifier, with no delexicalisation or dataset-specific heuristics. — [arXiv:2004.06577](https://arxiv.org/abs/2004.06577); [ACL PDF](https://aclanthology.org/2020.coling-main.218.pdf)
- **VCP (Ren, Zhang & Liu, ACM MMAsia 2025)** runs generation, then verification ("a simple rule to check for the presence of every keyword in the prediction"), then regeneration with error-correcting prompts. It targets small LMs (T5), which "frequently miss keywords". This is the closest published rule-based checker loop, but it repairs omissions; it does not gate hallucinated numerals, and it regenerates instead of failing closed. — [arXiv:2306.15933](https://arxiv.org/abs/2306.15933); [Crossref](https://api.crossref.org/works?query.bibliographic=You+Can+Generate+It+Again+Data-to-Text+Generation+with+Verification+and+Correction+Prompting+Ren&rows=1)
- **Constrained decoding:**
  - Balakrishnan et al. (ACL 2019) use tree-structured compositional meaning representations with constrained decoding for task-oriented NLG, motivated by controllability "in a live system". — [arXiv:1906.07220](https://arxiv.org/abs/1906.07220)
  - Geng et al. (EMNLP 2023) use grammar-constrained decoding to guarantee that output "follows a given structure" without fine-tuning. — [arXiv:2305.13971](https://arxiv.org/abs/2305.13971)
  - Rebuffel et al. (DMKD 2022) control hallucinations at the word level during D2T decoding. — [arXiv:2102.02810](https://arxiv.org/abs/2102.02810)
  - Thomson et al. (INLG 2023) use "data views" as a high-level schema for document planning; the neural model does micro-planning and realisation and "retains factual accuracy". — [ACL Anthology](https://aclanthology.org/2023.inlg-main.16/)
- **Programmatic verification of claims: ProgramFC (Pan et al., ACL 2023)** decomposes complex claims into reasoning programs whose sub-tasks are solved by a shared library of functions. — [arXiv:2305.12744](https://arxiv.org/abs/2305.12744)
- **MiniCheck (Tang, Laban & Durrett, EMNLP 2024)** shows how to build small fact-checking models for grounding LLM output in documents, avoiding the expense of many LLM calls per response. It is a neural (not symbolic) on-device-scale checker that could serve as a secondary verifier. — [arXiv:2404.10774](https://arxiv.org/abs/2404.10774)
- **Dušek's lecture summary of D2T accuracy techniques** lists overgenerate-and-rerank, data cleaning, auxiliary classifiers, explicit planning and "neural editing only", and notes that reranking "increases accuracy significantly but still can't guarantee it completely". The E2E slot-error-rate script is regex-based. This is a secondary source (lecture slides). — [Dušek 2021 slides](https://ufal.mff.cuni.cz/~odusek/2021/docs/gen-accuracy.pdf)

### Inferences
- CityPulse's Tier-0 template plus Tier-1 rewrite is T2G2 with a gate added. The novelty is the deterministic, typed, fail-closed gate (show the template if any check fails) applied to safety-relevant route text, not the template-rewrite idea itself. Cite Kale & Rastogi 2020 as the direct precedent, and DataTuner/VCP as "learned-reranker" and "regenerate" alternatives to fail-closed gating.
- Regex and slot-error checkers (E2E SER) are the honest ancestor of the numeral and entity checks. Comparative and hedge checks, and "no absolute-safety claims", have no direct D2T precedent that I found.

### Gaps
- I found no study measuring the false-reject rate (correct rewrites blocked) of a symbolic verifier. That trade-off (fluency lost vs. errors blocked) is unmeasured in prior work and is an evaluation opportunity.
- Schema-constrained decoding benchmarks (e.g., JSONSchemaBench) were not verified in this pass.

---

## Q4. How is hallucination measured in data-to-text, and what do benchmarks report?

### Takeaway
The accepted metrics are:
- slot error rate (SER) and regex checks;
- NLI-based semantic accuracy in both directions, which catches omissions and hallucinations;
- token- or span-level human error annotation by category (gold-standard methodology);
- reference-free LLM-as-judge error annotation;
- human-annotated hallucination benchmarks.

Zero-shot open LLMs make at least one semantic error in more than 80% of D2T outputs.

### Cited Findings
- **Dušek & Kasner (INLG 2020)** use an NLI model in both directions (data→text and text→data) to detect omissions and hallucinations. Input data are converted to text with "trivial templates". — [ACL PDF](https://aclanthology.org/2020.inlg-1.19.pdf)
- **Thomson & Reiter (INLG 2020)** define a gold-standard human methodology for annotating factual accuracy errors in D2T output. — [arXiv:2011.03992](https://arxiv.org/abs/2011.03992)
- **Kasner, Mille & Dušek (INLG 2021)**, the shared-task submission on evaluating accuracy, detect token-level errors by combining a rule-based NLG system (which generates derivable facts) with a fine-tuned LM. — [Exa library record](https://exa.ai/library/publication/glbp3tpc84g)
- **Kasner & Dušek (ACL 2024)** built Quintd, which collects fresh structured records from public APIs (OpenWeather, GSMArena, ice hockey, OWID, Wikidata) to avoid benchmark contamination. Open LLMs (Llama 2, Mistral, Zephyr) produce fluent text, but "more than 80% of the outputs of open LLMs contain at least one semantic error", according to both human annotators and a GPT-4-based reference-free metric. — [arXiv:2401.10186](https://arxiv.org/abs/2401.10186)
- **Maynez et al. (ACL 2020)** ran a large human evaluation showing that neural abstractive summarisers are "highly prone to hallucinate content that is unfaithful to the input document". This is the standard intrinsic/extrinsic hallucination framing. — [arXiv:2005.00661](https://arxiv.org/abs/2005.00661)
- **FaithBench (Bao et al., NAACL 2025)** is a summarisation hallucination benchmark with challenging hallucinations from 10 modern LLMs across 8 families and human-expert ground truth. It targets evaluation of hallucination detectors. — [arXiv:2410.13210](https://arxiv.org/abs/2410.13210)

### Inferences
- For CityPulse, the most comparable metric is a per-output binary "≥1 semantic error" rate (Quintd style), computed separately for numerals, entities and comparatives against the DecisionTrace. Report it before the gate (raw LM rewrite) and after the gate (shown text, which should be 0 by construction, plus a false-reject rate). Template-to-NLI checking (Dušek & Kasner) is a ready-made secondary, non-symbolic check.

### Gaps
- No D2T hallucination benchmark found uses routing or hazard records. Quintd's weather (OpenWeather) domain is the nearest numeric-heavy analogue.
- Size-stratified hallucination rates for models under 1B parameters on D2T were not found in a verified source.

---

## Q5. On-device small LMs on phones: latency, energy and accuracy (2024–2026)

### Takeaway
Measurement studies agree on several points:
- on-device LLM inference is memory-bound;
- quantisation makes it viable but costs accuracy;
- energy and thermal limits rule out continuous use;
- small LMs can match 7B models on general tasks but have weak in-context learning;
- on-device inference is, on average, less energy-efficient per token than batched server inference.

None of these studies measures hallucination on structured-data verbalisation, the CityPulse Tier-1 task.

### Cited Findings
- **MELT (Laskaridis et al., MobiCom 2024)** benchmarks LLMs headless on Android, iOS and Jetson, measuring performance, energy and accuracy. Inference "is largely memory-bound". Quantisation "drastically reduces memory requirements and renders execution viable, but at a non-negligible accuracy cost". Because of energy and thermal behaviour, "the continuous execution of LLMs remains elusive". — [arXiv:2403.12844](https://arxiv.org/abs/2403.12844v4); [Crossref](https://api.crossref.org/works?query.bibliographic=MELTing+point+Mobile+Evaluation+of+Language+Transformers+Laskaridis&rows=2)
- **Lu et al. (ACL 2025)** study more than 60 SLMs (e.g., Phi, Gemma). They find that "state-of-the-art SLMs outperform 7B models in general tasks", but in-context learning "remain[s] limited" and efficiency has "significant optimization potential". — [ACL Anthology](https://aclanthology.org/2025.acl-long.718/)
- **Lu et al. (2024 survey)** cover 70 decoder-only SLMs of 100M–5B parameters and benchmark on-device latency and memory. — [arXiv:2409.15790](https://arxiv.org/abs/2409.15790)
- **MobileAIBench (Murthy et al., 2024)** evaluates LLMs and LMMs across sizes and quantisation levels, including trust and safety, and measures latency and resource use on real iOS devices. — [arXiv:2406.10290](https://arxiv.org/abs/2406.10290)
- **llm.npu (Xu et al., ASPLOS 2025)** targets fast on-device LLM inference on mobile NPUs. — [Crossref](https://api.crossref.org/works?filter=doi:10.1145/3669940.3707239)
- **SmolLM2 (Allal et al., 2025)** is a data-centric training study of a small LM. Only the title, authors and opening of the abstract were read. — [arXiv:2502.02737](https://arxiv.org/abs/2502.02737)
- **Guégain & Coignion (arXiv 2026; ID/date caution in the table)** test 18 model configurations on two smartphones plus a server. Findings:
  - on-device inference is "on average 3 times less energy-efficient than batched server inference";
  - the relationship between quantisation bit-width and energy per token is non-monotonic;
  - 8 of the 18 configurations lie on the accuracy–energy Pareto front;
  - 88–90% of the per-token environmental impact comes from embodied carbon in the device.
  — [arXiv:2609.11940](https://arxiv.org/abs/2609.11940)
- **MobiBench (Hariharan et al., arXiv 2026; same caution)** is a single-runtime benchmark reporting prefill and decode speed, time to first token, memory and battery for edge LLMs. — [arXiv:2609.13159](https://arxiv.org/abs/2609.13159)

### Inferences
- These sources support Tier 1 being optional and on-demand rather than always-on (MELT on energy and thermals; Guégain & Coignion on energy per token). They also support a deterministic template as the default path on low-cost phones.
- Lu et al.'s finding that in-context learning is weak suggests few-shot prompting of a sub-1B rewriter (Gemma 270M) will be fragile. That raises the expected verifier rejection rate and makes the false-reject measurement important.

### Gaps
- No verified study reports Gemma-3-270M (or other models under 300M) latency or energy on low-cost (<US$150) Android phones, or hallucination rates for such models on numeric paraphrase. The team would need to measure this themselves.
- The "2609" arXiv items have an internal date inconsistency and should be re-checked before citing.

---

## Closest prior work to verified on-device route explanation

1. **Kale & Rastogi 2020 (T2G2)** has the same pipeline shape: templates first, then an LM rewrite. It has no runtime verifier and no fallback, and its domain is task-oriented dialogue, not routing. The CityPulse delta is the typed symbolic gate, fail-closed display, and the safety domain.
2. **Ren, Zhang & Liu 2025 (VCP)** pairs a small LM with a rule-based keyword checker and regeneration. It checks only for omissions (keyword presence), not hallucinated numerals, comparatives or hedges, and it regenerates rather than falling back. The CityPulse delta is that the verifier checks what is asserted (numerals, entities, comparatives, safety claims) and shows the template when a check fails.
3. **Harkous et al. 2020 (DataTuner)** uses a learned semantic-fidelity reranker. Its guarantee is probabilistic, and per Dušek's slides rerankers still "can't guarantee it completely". The CityPulse delta is a deterministic check.
4. **Kikuta et al. 2024 (RouteExplainer)** pairs a counterfactual route explanation with GPT-4 text and evaluates the text only qualitatively. It is the only route-domain system found that combines a route explainer with an LLM, and it has no faithfulness check, is cloud-only and covers VRP rather than hazard routing.
5. **Schild et al. 2025 (SVE) and Alsheeb & Brandão 2023** give algorithmic answers to "why this route", based on traffic, closures and speed limits, without NL generation or faithfulness checks. They are the natural source of the explanation content that a DecisionTrace would hold.
6. **Ilyankou et al. 2026** argue conceptually that LLM navigation should be neuro-symbolic, with verifiable pathfinding grounding the persuasive text. CityPulse is a concrete instance of that recommendation; cite it as motivation.
7. **Lei et al. 2025** names hallucinated evacuation routes as a disaster-LLM risk, with only RAG, fine-tuning and uncertainty estimation as mitigations. CityPulse's gate is a direct answer to this stated challenge.

**Bottom line:** in this search I found no prior work that (a) explains route or navigation choices under hazard uncertainty in natural language, (b) uses an LM rewrite gated by a symbolic verifier against the decision record, (c) falls back to a template on failure, or (d) runs on-device. Each element has precedent separately: T2G2 for the template-rewrite, VCP and SER for rule checks, SVE and inverse optimisation for route explanation, and MELT and Lu et al. for on-device SLMs. The combination does not appear to be published. This is an absence-of-evidence claim, limited to the queries run here (Exa web search, arXiv, Crossref and one WebSearch; the Consensus quota was exhausted).

## Gaps

- **Faithfulness metrics in the route domain:** no route-explanation paper reports text-faithfulness numbers, so there is no baseline. CityPulse would be the first to report pre-gate error rate, post-gate error rate and false-reject rate for route explanations; this has to be built, not cited.
- **Hallucination by model size under 1B on D2T:** no verified source. The Vectara HHEM leaderboard and FaithBench cover larger models.
- **Evidence on low-cost phones:** MELT, MobileAIBench and the battery study use flagship or modern phones. There is no verified data for budget Android devices typical in Chennai.
- **User-study evidence on hedged or uncertain route explanations:** Thill et al. 2018 (explanations increase adherence) and Vredenborg et al. 2026 (tone) are the nearest. No study found tests whether verified, hedged LLM text beats templates on trust calibration in a hazard context.
- **Unverified leads** are listed under the table and should be checked before use. The geospatial-hallucination paper (Findings of EMNLP 2025) is the most likely to be relevant.
- **Tooling limits this session:** shell network egress was blocked, Consensus had no searches left this month, and the arXiv 2609.* records show a date/ID inconsistency.
