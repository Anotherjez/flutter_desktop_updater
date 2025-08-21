// ignore_for_file: public_member_api_docs, sort_constructors_first
class AppArchiveModel {
  AppArchiveModel({
    required this.appName,
    required this.description,
    required this.items,
  });

  factory AppArchiveModel.fromJson(Map<String, dynamic> json) {
    return AppArchiveModel(
      appName: json["appName"],
      description: json["description"],
      items: List<ItemModel>.from(
        json["items"].map((x) => ItemModel.fromJson(x)),
      ),
    );
  }
  final String appName;
  final String description;
  final List<ItemModel> items;

  Map<String, dynamic> toJson() {
    return {
      "appName": appName,
      "description": description,
      "items": List<dynamic>.from(items.map((x) => x.toJson())),
    };
  }
}

class ItemModel {
  ItemModel({
    required this.version,
    required this.shortVersion,
    required this.changes,
    required this.date,
    required this.mandatory,
    required this.url,
    required this.platform,
    this.changedFiles,
    this.appName,
  });

  factory ItemModel.fromJson(Map<String, dynamic> json) {
    return ItemModel(
      version: json["version"],
      shortVersion: json["shortVersion"],
      changes: List<ChangeModel>.from(
        json["changes"].map((x) => ChangeModel.fromJson(x)),
      ),
      date: json["date"],
      mandatory: json["mandatory"],
      url: json["url"],
      platform: json["platform"],
    );
  }
  final String version;
  final int shortVersion;
  final List<ChangeModel> changes;
  final String date;
  final bool mandatory;
  final String url;
  final String platform;
  final List<FileHashModel?>? changedFiles;
  final String? appName;

  Map<String, dynamic> toJson() {
    return {
      "version": version,
      "shortVersion": shortVersion,
      "changes": List<dynamic>.from(changes.map((x) => x.toJson())),
      "date": date,
      "mandatory": mandatory,
      "url": url,
      "platform": platform,
    };
  }

  ItemModel copyWith({
    String? version,
    int? shortVersion,
    List<ChangeModel>? changes,
    String? date,
    bool? mandatory,
    String? url,
    String? platform,
    List<FileHashModel?>? changedFiles,
    String? appName,
  }) {
    return ItemModel(
      version: version ?? this.version,
      shortVersion: shortVersion ?? this.shortVersion,
      changes: changes ?? this.changes,
      date: date ?? this.date,
      mandatory: mandatory ?? this.mandatory,
      url: url ?? this.url,
      platform: platform ?? this.platform,
      changedFiles: changedFiles ?? changedFiles,
      appName: appName ?? this.appName,
    );
  }
}

class ChangeModel {
  ChangeModel({this.type, required this.message});

  factory ChangeModel.fromJson(Map<String, dynamic> json) {
    return ChangeModel(type: json["type"], message: json["message"]);
  }
  final String? type;
  final String message;

  Map<String, dynamic> toJson() {
    return {"type": type, "message": message};
  }
}

class FileHashModel {
  FileHashModel({
    required this.filePath,
    required this.calculatedHash,
    required this.length,
  });

  factory FileHashModel.fromJson(Map<String, dynamic> json) {
    return FileHashModel(
      filePath: json["path"],
      calculatedHash: json["calculatedHash"],
      length: json["length"],
    );
  }
  final String filePath;
  final String calculatedHash;
  final int length;

  Map<String, dynamic> toJson() {
    return {
      "path": filePath,
      "calculatedHash": calculatedHash,
      "length": length,
    };
  }
}
