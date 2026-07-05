import 'package:shared_preferences/shared_preferences.dart';

class TaskStorage {
  static const String _activeTaskKey = 'active_task_id';
  static const String _pathPrefix = 'task_video_path_';
  static const String _namePrefix = 'task_video_name_';

  Future<void> saveActiveTask({
    required String taskId,
    required String videoPath,
    required String videoName,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setString(_activeTaskKey, taskId),
      preferences.setString('$_pathPrefix$taskId', videoPath),
      preferences.setString('$_namePrefix$taskId', videoName),
    ]);
  }

  Future<String?> getActiveTaskId() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_activeTaskKey);
  }

  Future<StoredUpload?> getUpload(String taskId) async {
    final preferences = await SharedPreferences.getInstance();
    final path = preferences.getString('$_pathPrefix$taskId');
    if (path == null || path.isEmpty) return null;
    return StoredUpload(
      taskId: taskId,
      videoPath: path,
      videoName: preferences.getString('$_namePrefix$taskId') ?? '',
    );
  }

  Future<void> clearActiveTask(String taskId) async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getString(_activeTaskKey) == taskId) {
      await preferences.remove(_activeTaskKey);
    }
  }

  Future<void> removeUpload(String taskId) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      clearActiveTask(taskId),
      preferences.remove('$_pathPrefix$taskId'),
      preferences.remove('$_namePrefix$taskId'),
    ]);
  }
}

class StoredUpload {
  const StoredUpload({
    required this.taskId,
    required this.videoPath,
    required this.videoName,
  });

  final String taskId;
  final String videoPath;
  final String videoName;
}
