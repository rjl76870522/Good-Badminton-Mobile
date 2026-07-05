import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:good_badminton_mobile/services/task_storage.dart';
import 'package:good_badminton_mobile/services/user_storage.dart';

void main() {
  test('active task and retry upload survive storage reads', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = TaskStorage();

    await storage.saveActiveTask(
      taskId: 'task-1',
      videoPath: r'C:\videos\sample.mp4',
      videoName: 'sample.mp4',
    );

    expect(await storage.getActiveTaskId(), 'task-1');
    final upload = await storage.getUpload('task-1');
    expect(upload, isNotNull);
    expect(upload!.videoPath, r'C:\videos\sample.mp4');
    expect(upload.videoName, 'sample.mp4');

    await storage.clearActiveTask('task-1');
    expect(await storage.getActiveTaskId(), isNull);
    expect(await storage.getUpload('task-1'), isNotNull);

    await storage.removeUpload('task-1');
    expect(await storage.getUpload('task-1'), isNull);
  });

  test('guest user id is generated once and remains stable', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = UserStorage();

    final first = await storage.getOrCreateUserId();
    final second = await UserStorage().getOrCreateUserId();

    expect(first, startsWith('guest_'));
    expect(first, second);

    await storage.setNickname('  小羽  ');
    expect(await storage.getNickname(), '小羽');
  });
}
