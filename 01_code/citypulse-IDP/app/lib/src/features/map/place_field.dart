/// A text field that searches street names as you type.
library;

import 'dart:async';

import 'package:citypulse_app/src/core/settings.dart';
import 'package:citypulse_app/src/core/strings.dart';
import 'package:citypulse_app/src/domain/models.dart';
import 'package:citypulse_app/src/platform/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pulse_router/pulse_router.dart';

/// One place input (start or destination) with live suggestions.
class PlaceField extends ConsumerStatefulWidget {
  /// Creates the field. [near] reports the map centre so equally good matches
  /// are ordered nearest first.
  const PlaceField({
    required this.fieldKey,
    required this.label,
    required this.place,
    required this.onSelected,
    required this.near,
    this.onUseMapCentre,
    super.key,
  });

  /// Prefix for widget keys (`place-field-<fieldKey>`), used by tests.
  final String fieldKey;

  /// Field label.
  final String label;

  /// The current choice, shown in the field.
  final Place? place;

  /// Called when the traveller picks a suggestion.
  final void Function(Place place) onSelected;

  /// The map centre, for ranking.
  final GeoPoint? Function() near;

  /// Called when the "use map centre" button is pressed.
  final VoidCallback? onUseMapCentre;

  @override
  ConsumerState<PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends ConsumerState<PlaceField> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Place> _suggestions = const [];
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.place?.name ?? '';
  }

  @override
  void didUpdateWidget(PlaceField old) {
    super.didUpdateWidget(old);
    if (widget.place != old.place) {
      _controller.text = widget.place?.name ?? '';
      _suggestions = const [];
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final mine = ++_generation;
    if (text.trim().length < 2) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final backend = ref.read(routingBackendProvider);
        await backend.warmUp();
        final found = await backend.searchPlaces(text, near: widget.near());
        if (!mounted || mine != _generation) return;
        setState(() => _suggestions = found);
        // A search that cannot run (offline server, data still loading)
        // should leave the field usable, not throw into the UI.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        if (mounted && mine == _generation)
          setState(() => _suggestions = const []);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: Key('place-field-${widget.fieldKey}'),
          controller: _controller,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: s(Msg.searchHint),
            prefixIcon: Icon(
              widget.fieldKey == 'origin'
                  ? Icons.trip_origin
                  : Icons.place_outlined,
            ),
            suffixIcon: widget.onUseMapCentre == null
                ? null
                : IconButton(
                    key: Key('use-centre-${widget.fieldKey}'),
                    tooltip: s(Msg.useMapCentre),
                    icon: const Icon(Icons.my_location),
                    onPressed: widget.onUseMapCentre,
                  ),
          ),
          onChanged: _onChanged,
        ),
        if (_suggestions.isNotEmpty)
          Card(
            elevation: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _suggestions.length; i++)
                  ListTile(
                    key: Key('suggestion-${widget.fieldKey}-$i'),
                    dense: true,
                    leading: const Icon(Icons.signpost_outlined, size: 20),
                    title: Text(_suggestions[i].name),
                    subtitle: _suggestions[i].detail == null
                        ? null
                        : Text(_suggestions[i].detail!),
                    onTap: () {
                      final chosen = _suggestions[i];
                      setState(() => _suggestions = const []);
                      FocusScope.of(context).unfocus();
                      widget.onSelected(chosen);
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
