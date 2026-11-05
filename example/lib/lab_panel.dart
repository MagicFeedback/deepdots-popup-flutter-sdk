import 'dart:io';

import 'package:deepdots_popups/deepdots_popups.dart';
import 'package:flutter/material.dart';

import 'lab.dart';
import 'main.dart';

/// SDK Lab: what this run is (version, env, ids), what to test next, and the run log.
class LabPanel extends StatefulWidget {
  const LabPanel({
    super.key,
    required this.host,
    required this.onEvent,
    required this.onBurst,
    required this.onInitAgain,
    required this.onRapidCheckout,
  });

  final SdkHost host;
  final void Function(String event) onEvent;
  final void Function(String event) onBurst;
  final VoidCallback onInitAgain;
  final VoidCallback onRapidCheckout;

  @override
  State<LabPanel> createState() => _LabPanelState();
}

class _LabPanelState extends State<LabPanel> {
  late LabConfig _draft = widget.host.config;

  SdkHost get _host => widget.host;

  Future<String> _id(Future<String?> Function() read) async =>
      _host.initialized.value ? await read() ?? '—' : 'not initialized';

  /// A Flutter app cannot restart itself: the new config applies on the next launch.
  Future<void> _applyAndQuit() async {
    await _draft.save();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Saved'),
        content: const Text('The app will quit. Launch it again to start the new run.'),
        actions: [TextButton(onPressed: () => exit(0), child: const Text('Quit app'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final events = _host.scenarios.events(_host.config.scenario);
    return Scaffold(
      appBar: AppBar(
        title: const Text('SDK Lab'),
        automaticallyImplyLeading: false,
        actions: [
          Semantics(
            identifier: 'lab-close',
            child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _info('SDK', '$nativeSdkVersion · Flutter', 'lab-info-version'),
          _info('Environment', 'DEV · ${devAPI.replaceFirst('https://', '')}', 'lab-info-env'),
          _info('Public key', _host.publicKey, 'lab-info-key'),
          _asyncInfo('User id', _id(DeepdotsPopups.getUserId), 'lab-info-user'),
          _asyncInfo('Session id', _id(DeepdotsPopups.getSessionId), 'lab-info-session'),
          const _Header('Run'),
          _picker(
            'Scenario',
            'lab-scenario-picker',
            _draft.scenario,
            _host.scenarios.names,
            (v) => _draft = _draft.copyWith(scenario: v),
          ),
          _picker('Navigation', 'lab-nav-picker', _draft.nav, const [
            'history',
            'silent',
          ], (v) => _draft = _draft.copyWith(nav: v)),
          _picker('Language', 'lab-lang-picker', _draft.lang, const [
            'en',
            'es',
          ], (v) => _draft = _draft.copyWith(lang: v)),
          _picker('Load', 'lab-load-picker', _draft.load, const [
            'immediate',
            'consent',
          ], (v) => _draft = _draft.copyWith(load: v)),
          Semantics(
            identifier: 'lab-apply',
            child: ListTile(title: const Text('Apply & quit'), onTap: _applyAndQuit),
          ),
          Semantics(
            identifier: 'lab-init-again',
            child: ListTile(title: const Text('Init again (same options)'), onTap: widget.onInitAgain),
          ),
          Semantics(
            identifier: 'lab-rapid-checkout',
            child: ListTile(title: const Text('Rapid nav: cart ⇄ checkout ×3'), onTap: widget.onRapidCheckout),
          ),
          if (events.isNotEmpty) ...[
            const _Header('Host events'),
            for (final e in events) ...[
              Semantics(
                identifier: 'lab-event-$e',
                child: ListTile(title: Text(e), onTap: () => widget.onEvent(e)),
              ),
              Semantics(
                identifier: 'lab-burst-$e',
                child: ListTile(title: Text('$e ×3'), onTap: () => widget.onBurst(e)),
              ),
            ],
          ],
          const _Header('Log · [lab]'),
          Semantics(
            identifier: 'lab-panel-log',
            child: ValueListenableBuilder(
              valueListenable: Lab.lines,
              builder: (_, lines, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in lines.length > 40 ? lines.sublist(lines.length - 40) : lines)
                      Text(line, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _info(String label, String value, String id) => ListTile(
    dense: true,
    title: Text(label),
    trailing: Semantics(
      identifier: id,
      child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
  );

  Widget _asyncInfo(String label, Future<String> value, String id) =>
      FutureBuilder(future: value, builder: (_, snapshot) => _info(label, snapshot.data ?? '…', id));

  Widget _picker(String label, String id, String value, List<String> options, void Function(String) onChanged) =>
      ListTile(
        dense: true,
        title: Text(label),
        trailing: Semantics(
          identifier: id,
          child: DropdownButton<String>(
            value: value,
            items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o))],
            onChanged: (v) => setState(() => onChanged(v!)),
          ),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(title, style: Theme.of(context).textTheme.labelLarge),
  );
}
