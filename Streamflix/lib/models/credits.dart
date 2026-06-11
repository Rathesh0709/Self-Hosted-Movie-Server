class CastMember {
  final int id;
  final String name;
  final String character;
  final String? profilePath;
  const CastMember({
    required this.id,
    required this.name,
    this.character = '',
    this.profilePath,
  });
  factory CastMember.fromJson(Map<String, dynamic> j) => CastMember(
        id: j['id'] as int,
        name: (j['name'] ?? '') as String,
        character: (j['character'] ?? '') as String,
        profilePath: j['profile_path'] as String?,
      );
}

class Credits {
  final List<CastMember> cast;
  const Credits({this.cast = const []});
  factory Credits.fromJson(Map<String, dynamic> j) => Credits(
        cast: (j['cast'] as List?)
                ?.map((c) => CastMember.fromJson(c as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}
