class Bookmark {
  const Bookmark({
    required this.id,
    required this.name,
    required this.url,
  });

  final String id;
  final String name;
  final String url;

  Bookmark copyWith({String? name, String? url}) {
    return Bookmark(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
      };

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    return Bookmark(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? json['title'] ?? ''}'.trim(),
      url: '${json['url'] ?? json['href'] ?? ''}'.trim(),
    );
  }
}
