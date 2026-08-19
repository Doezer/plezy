import 'package:json_annotation/json_annotation.dart';

import '../utils/json_utils.dart';

part 'media_role.g.dart';

/// A cast or crew member attached to a media item.
@JsonSerializable(includeIfNull: false)
class MediaRole {
  final String? id;
  @JsonKey(fromJson: stringOrEmpty)
  final String tag;
  final String? role;
  final String? thumbPath;

  /// The person's stable cross-server identifier (Plex `tagKey`), when the
  /// backend's agent populated one. Distinct from [id], which is only a
  /// local per-server tag id: on Plex this is the id used against
  /// `discover.provider.plex.tv/library/people/{personKey}` for the person's
  /// cloud "Known For"/filmography data, and is null for backends (or
  /// unmatched libraries) with no such global identity.
  final String? personKey;

  const MediaRole({this.id, required this.tag, this.role, this.thumbPath, this.personKey});

  factory MediaRole.fromJson(Map<String, dynamic> json) => _$MediaRoleFromJson(json);

  Map<String, dynamic> toJson() => _$MediaRoleToJson(this);
}
