class ApiConstants {
  static const String tmdbApiKey = "8265bd1679663a7ea12ac168da84d2e8";
  static const String tmdbBaseUrl = "https://api.themoviedb.org/3";
  static const String tmdbImageBaseUrl = "https://image.tmdb.org/t/p";

  static String getImageUrl(String? path, {String size = "w500"}) {
    if (path == null || path.isEmpty) return "";
    return "$tmdbImageBaseUrl/$size$path";
  }

  static String getOriginalImageUrl(String? path) {
    if (path == null || path.isEmpty) return "";
    return "$tmdbImageBaseUrl/original$path";
  }
}
