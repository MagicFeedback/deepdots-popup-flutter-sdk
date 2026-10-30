import 'package:deepdots_popups/deepdots_popups.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// `getFeedbackSessionId` y `onFeedbackSession` del SDK nativo (0.7.0).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.deepdots/popups');
  const codec = StandardMethodCodec();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() async {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'getFeedbackSessionId' ? 'fs-1' : null;
    });
    await DeepdotsPopups.init(publicKey: 'pk');
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> fromNative(Map<String, Object?> payload) => messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(MethodCall('onFeedbackSession', payload)),
        (_) {},
      );

  test('getFeedbackSessionId devuelve el id nativo', () async {
    expect(await DeepdotsPopups.getFeedbackSessionId(), 'fs-1');
    expect(calls.last.method, 'getFeedbackSessionId');
  });

  test('onFeedbackSession llega a feedbackSessions con open y closed', () async {
    final received = <DeepdotsFeedbackSession>[];
    final sub = DeepdotsPopups.feedbackSessions.listen(received.add);
    await fromNative({'sessionId': 'fs-1', 'status': 'open'});
    await fromNative({'sessionId': 'fs-1', 'status': 'closed'});
    await pumpEventQueue();
    await sub.cancel();
    expect(received.map((s) => '${s.sessionId}:${s.closed}'), ['fs-1:false', 'fs-1:true']);
  });
}
