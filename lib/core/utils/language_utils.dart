class LanguageInfo {
  final String flag;
  final String code;
  final String name;

  const LanguageInfo({
    required this.flag,
    required this.code,
    required this.name,
  });
}

class LanguageUtils {
  static const Map<String, LanguageInfo> _known = {
    'en': LanguageInfo(flag: '🇺🇸', code: 'EN', name: 'English'),
    'eng': LanguageInfo(flag: '🇺🇸', code: 'EN', name: 'English'),
    'english': LanguageInfo(flag: '🇺🇸', code: 'EN', name: 'English'),

    'es': LanguageInfo(flag: '🇪🇸', code: 'ES', name: 'Spanish'),
    'spa': LanguageInfo(flag: '🇪🇸', code: 'ES', name: 'Spanish'),
    'spanish': LanguageInfo(flag: '🇪🇸', code: 'ES', name: 'Spanish'),
    'español': LanguageInfo(flag: '🇪🇸', code: 'ES', name: 'Spanish'),

    'fr': LanguageInfo(flag: '🇫🇷', code: 'FR', name: 'French'),
    'fra': LanguageInfo(flag: '🇫🇷', code: 'FR', name: 'French'),
    'fre': LanguageInfo(flag: '🇫🇷', code: 'FR', name: 'French'),
    'french': LanguageInfo(flag: '🇫🇷', code: 'FR', name: 'French'),
    'français': LanguageInfo(flag: '🇫🇷', code: 'FR', name: 'French'),

    'de': LanguageInfo(flag: '🇩🇪', code: 'DE', name: 'German'),
    'deu': LanguageInfo(flag: '🇩🇪', code: 'DE', name: 'German'),
    'ger': LanguageInfo(flag: '🇩🇪', code: 'DE', name: 'German'),
    'german': LanguageInfo(flag: '🇩🇪', code: 'DE', name: 'German'),
    'deutsch': LanguageInfo(flag: '🇩🇪', code: 'DE', name: 'German'),

    'it': LanguageInfo(flag: '🇮🇹', code: 'IT', name: 'Italian'),
    'ita': LanguageInfo(flag: '🇮🇹', code: 'IT', name: 'Italian'),
    'italian': LanguageInfo(flag: '🇮🇹', code: 'IT', name: 'Italian'),
    'italiano': LanguageInfo(flag: '🇮🇹', code: 'IT', name: 'Italian'),

    'pt': LanguageInfo(flag: '🇧🇷', code: 'PT', name: 'Portuguese'),
    'por': LanguageInfo(flag: '🇧🇷', code: 'PT', name: 'Portuguese'),
    'portuguese': LanguageInfo(flag: '🇧🇷', code: 'PT', name: 'Portuguese'),
    'português': LanguageInfo(flag: '🇧🇷', code: 'PT', name: 'Portuguese'),

    'ru': LanguageInfo(flag: '🇷🇺', code: 'RU', name: 'Russian'),
    'rus': LanguageInfo(flag: '🇷🇺', code: 'RU', name: 'Russian'),
    'russian': LanguageInfo(flag: '🇷🇺', code: 'RU', name: 'Russian'),
    'русский': LanguageInfo(flag: '🇷🇺', code: 'RU', name: 'Russian'),

    'hi': LanguageInfo(flag: '🇮🇳', code: 'HI', name: 'Hindi'),
    'hin': LanguageInfo(flag: '🇮🇳', code: 'HI', name: 'Hindi'),
    'hindi': LanguageInfo(flag: '🇮🇳', code: 'HI', name: 'Hindi'),
    'हिन्दी': LanguageInfo(flag: '🇮🇳', code: 'HI', name: 'Hindi'),

    'ja': LanguageInfo(flag: '🇯🇵', code: 'JA', name: 'Japanese'),
    'jpn': LanguageInfo(flag: '🇯🇵', code: 'JA', name: 'Japanese'),
    'japanese': LanguageInfo(flag: '🇯🇵', code: 'JA', name: 'Japanese'),
    '日本語': LanguageInfo(flag: '🇯🇵', code: 'JA', name: 'Japanese'),

    'ko': LanguageInfo(flag: '🇰🇷', code: 'KO', name: 'Korean'),
    'kor': LanguageInfo(flag: '🇰🇷', code: 'KO', name: 'Korean'),
    'korean': LanguageInfo(flag: '🇰🇷', code: 'KO', name: 'Korean'),
    '한국어': LanguageInfo(flag: '🇰🇷', code: 'KO', name: 'Korean'),

    'zh': LanguageInfo(flag: '🇨🇳', code: 'ZH', name: 'Chinese'),
    'zho': LanguageInfo(flag: '🇨🇳', code: 'ZH', name: 'Chinese'),
    'chi': LanguageInfo(flag: '🇨🇳', code: 'ZH', name: 'Chinese'),
    'chinese': LanguageInfo(flag: '🇨🇳', code: 'ZH', name: 'Chinese'),
    '中文': LanguageInfo(flag: '🇨🇳', code: 'ZH', name: 'Chinese'),

    'ar': LanguageInfo(flag: '🇸🇦', code: 'AR', name: 'Arabic'),
    'ara': LanguageInfo(flag: '🇸🇦', code: 'AR', name: 'Arabic'),
    'arabic': LanguageInfo(flag: '🇸🇦', code: 'AR', name: 'Arabic'),
    'العربية': LanguageInfo(flag: '🇸🇦', code: 'AR', name: 'Arabic'),

    'tr': LanguageInfo(flag: '🇹🇷', code: 'TR', name: 'Turkish'),
    'tur': LanguageInfo(flag: '🇹🇷', code: 'TR', name: 'Turkish'),
    'turkish': LanguageInfo(flag: '🇹🇷', code: 'TR', name: 'Turkish'),
    'türkçe': LanguageInfo(flag: '🇹🇷', code: 'TR', name: 'Turkish'),

    'id': LanguageInfo(flag: '🇮🇩', code: 'ID', name: 'Indonesian'),
    'ind': LanguageInfo(flag: '🇮🇩', code: 'ID', name: 'Indonesian'),
    'indonesian': LanguageInfo(flag: '🇮🇩', code: 'ID', name: 'Indonesian'),

    'ms': LanguageInfo(flag: '🇲🇾', code: 'MS', name: 'Malay'),
    'may': LanguageInfo(flag: '🇲🇾', code: 'MS', name: 'Malay'),
    'msa': LanguageInfo(flag: '🇲🇾', code: 'MS', name: 'Malay'),
    'malay': LanguageInfo(flag: '🇲🇾', code: 'MS', name: 'Malay'),

    'pa': LanguageInfo(flag: '🇮🇳', code: 'PA', name: 'Punjabi'),
    'pan': LanguageInfo(flag: '🇮🇳', code: 'PA', name: 'Punjabi'),
    'punjabi': LanguageInfo(flag: '🇮🇳', code: 'PA', name: 'Punjabi'),
    'ਪੰਜਾਬੀ': LanguageInfo(flag: '🇮🇳', code: 'PA', name: 'Punjabi'),

    'ur': LanguageInfo(flag: '🇵🇰', code: 'UR', name: 'Urdu'),
    'urd': LanguageInfo(flag: '🇵🇰', code: 'UR', name: 'Urdu'),
    'urdu': LanguageInfo(flag: '🇵🇰', code: 'UR', name: 'Urdu'),
    'اُردُو': LanguageInfo(flag: '🇵🇰', code: 'UR', name: 'Urdu'),

    'sw': LanguageInfo(flag: '🇰🇪', code: 'SW', name: 'Swahili'),
    'swa': LanguageInfo(flag: '🇰🇪', code: 'SW', name: 'Swahili'),
    'swahili': LanguageInfo(flag: '🇰🇪', code: 'SW', name: 'Swahili'),
    'kiswahili': LanguageInfo(flag: '🇰🇪', code: 'SW', name: 'Swahili'),

    'vi': LanguageInfo(flag: '🇻🇳', code: 'VI', name: 'Vietnamese'),
    'vie': LanguageInfo(flag: '🇻🇳', code: 'VI', name: 'Vietnamese'),
    'vietnamese': LanguageInfo(flag: '🇻🇳', code: 'VI', name: 'Vietnamese'),
    'tiếng việt': LanguageInfo(flag: '🇻🇳', code: 'VI', name: 'Vietnamese'),

    'th': LanguageInfo(flag: '🇹🇭', code: 'TH', name: 'Thai'),
    'tha': LanguageInfo(flag: '🇹🇭', code: 'TH', name: 'Thai'),
    'thai': LanguageInfo(flag: '🇹🇭', code: 'TH', name: 'Thai'),
    'ไทย': LanguageInfo(flag: '🇹🇭', code: 'TH', name: 'Thai'),

    'pl': LanguageInfo(flag: '🇵🇱', code: 'PL', name: 'Polish'),
    'pol': LanguageInfo(flag: '🇵🇱', code: 'PL', name: 'Polish'),
    'polish': LanguageInfo(flag: '🇵🇱', code: 'PL', name: 'Polish'),
    'polski': LanguageInfo(flag: '🇵🇱', code: 'PL', name: 'Polish'),

    'nl': LanguageInfo(flag: '🇳🇱', code: 'NL', name: 'Dutch'),
    'nld': LanguageInfo(flag: '🇳🇱', code: 'NL', name: 'Dutch'),
    'dut': LanguageInfo(flag: '🇳🇱', code: 'NL', name: 'Dutch'),
    'dutch': LanguageInfo(flag: '🇳🇱', code: 'NL', name: 'Dutch'),
    'nederlands': LanguageInfo(flag: '🇳🇱', code: 'NL', name: 'Dutch'),

    'sv': LanguageInfo(flag: '🇸🇪', code: 'SV', name: 'Swedish'),
    'swe': LanguageInfo(flag: '🇸🇪', code: 'SV', name: 'Swedish'),
    'swedish': LanguageInfo(flag: '🇸🇪', code: 'SV', name: 'Swedish'),
    'svenska': LanguageInfo(flag: '🇸🇪', code: 'SV', name: 'Swedish'),

    'el': LanguageInfo(flag: '🇬🇷', code: 'EL', name: 'Greek'),
    'ell': LanguageInfo(flag: '🇬🇷', code: 'EL', name: 'Greek'),
    'gre': LanguageInfo(flag: '🇬🇷', code: 'EL', name: 'Greek'),
    'greek': LanguageInfo(flag: '🇬🇷', code: 'EL', name: 'Greek'),
    'ελληνικά': LanguageInfo(flag: '🇬🇷', code: 'EL', name: 'Greek'),

    'he': LanguageInfo(flag: '🇮🇱', code: 'HE', name: 'Hebrew'),
    'heb': LanguageInfo(flag: '🇮🇱', code: 'HE', name: 'Hebrew'),
    'hebrew': LanguageInfo(flag: '🇮🇱', code: 'HE', name: 'Hebrew'),
    'עברית': LanguageInfo(flag: '🇮🇱', code: 'HE', name: 'Hebrew'),

    'cs': LanguageInfo(flag: '🇨🇿', code: 'CS', name: 'Czech'),
    'ces': LanguageInfo(flag: '🇨🇿', code: 'CS', name: 'Czech'),
    'cze': LanguageInfo(flag: '🇨🇿', code: 'CS', name: 'Czech'),
    'czech': LanguageInfo(flag: '🇨🇿', code: 'CS', name: 'Czech'),
    'čeština': LanguageInfo(flag: '🇨🇿', code: 'CS', name: 'Czech'),

    'da': LanguageInfo(flag: '🇩🇰', code: 'DA', name: 'Danish'),
    'dan': LanguageInfo(flag: '🇩🇰', code: 'DA', name: 'Danish'),
    'danish': LanguageInfo(flag: '🇩🇰', code: 'DA', name: 'Danish'),
    'dansk': LanguageInfo(flag: '🇩🇰', code: 'DA', name: 'Danish'),

    'fi': LanguageInfo(flag: '🇫🇮', code: 'FI', name: 'Finnish'),
    'fin': LanguageInfo(flag: '🇫🇮', code: 'FI', name: 'Finnish'),
    'finnish': LanguageInfo(flag: '🇫🇮', code: 'FI', name: 'Finnish'),
    'suomi': LanguageInfo(flag: '🇫🇮', code: 'FI', name: 'Finnish'),

    'no': LanguageInfo(flag: '🇳🇴', code: 'NO', name: 'Norwegian'),
    'nor': LanguageInfo(flag: '🇳🇴', code: 'NO', name: 'Norwegian'),
    'norwegian': LanguageInfo(flag: '🇳🇴', code: 'NO', name: 'Norwegian'),
    'norsk': LanguageInfo(flag: '🇳🇴', code: 'NO', name: 'Norwegian'),

    'hu': LanguageInfo(flag: '🇭🇺', code: 'HU', name: 'Hungarian'),
    'hun': LanguageInfo(flag: '🇭🇺', code: 'HU', name: 'Hungarian'),
    'hungarian': LanguageInfo(flag: '🇭🇺', code: 'HU', name: 'Hungarian'),
    'magyar': LanguageInfo(flag: '🇭🇺', code: 'HU', name: 'Hungarian'),

    'ro': LanguageInfo(flag: '🇷🇴', code: 'RO', name: 'Romanian'),
    'ron': LanguageInfo(flag: '🇷🇴', code: 'RO', name: 'Romanian'),
    'rum': LanguageInfo(flag: '🇷🇴', code: 'RO', name: 'Romanian'),
    'romanian': LanguageInfo(flag: '🇷🇴', code: 'RO', name: 'Romanian'),
    'română': LanguageInfo(flag: '🇷🇴', code: 'RO', name: 'Romanian'),

    'uk': LanguageInfo(flag: '🇺🇦', code: 'UK', name: 'Ukrainian'),
    'ukr': LanguageInfo(flag: '🇺🇦', code: 'UK', name: 'Ukrainian'),
    'ukrainian': LanguageInfo(flag: '🇺🇦', code: 'UK', name: 'Ukrainian'),
    'українська': LanguageInfo(flag: '🇺🇦', code: 'UK', name: 'Ukrainian'),

    'tl': LanguageInfo(flag: '🇵🇭', code: 'TL', name: 'Filipino'),
    'tgl': LanguageInfo(flag: '🇵🇭', code: 'TL', name: 'Filipino'),
    'filipino': LanguageInfo(flag: '🇵🇭', code: 'TL', name: 'Filipino'),
    'tagalog': LanguageInfo(flag: '🇵🇭', code: 'TL', name: 'Filipino'),

    'ta': LanguageInfo(flag: '🇮🇳', code: 'TA', name: 'Tamil'),
    'tam': LanguageInfo(flag: '🇮🇳', code: 'TA', name: 'Tamil'),
    'tamil': LanguageInfo(flag: '🇮🇳', code: 'TA', name: 'Tamil'),
    'தமிழ்': LanguageInfo(flag: '🇮🇳', code: 'TA', name: 'Tamil'),

    'te': LanguageInfo(flag: '🇮🇳', code: 'TE', name: 'Telugu'),
    'tel': LanguageInfo(flag: '🇮🇳', code: 'TE', name: 'Telugu'),
    'telugu': LanguageInfo(flag: '🇮🇳', code: 'TE', name: 'Telugu'),
    'తెలుగు': LanguageInfo(flag: '🇮🇳', code: 'TE', name: 'Telugu'),

    'bn': LanguageInfo(flag: '🇧🇩', code: 'BN', name: 'Bengali'),
    'ben': LanguageInfo(flag: '🇧🇩', code: 'BN', name: 'Bengali'),
    'bengali': LanguageInfo(flag: '🇧🇩', code: 'BN', name: 'Bengali'),
    'বাংলা': LanguageInfo(flag: '🇧🇩', code: 'BN', name: 'Bengali'),
  };

  /// Resolves any language code or label into a structured LanguageInfo with flag, code, and title.
  static LanguageInfo getInfo(String input) {
    final clean = input.trim().toLowerCase();
    if (_known.containsKey(clean)) {
      return _known[clean]!;
    }

    // Check if input contains a known language name
    for (final entry in _known.entries) {
      if (entry.key.length > 2 && clean.contains(entry.key)) {
        return entry.value;
      }
    }

    // Default fallback with uppercase short code
    final shortCode = input.trim().length <= 3
        ? input.trim().toUpperCase()
        : input.trim().substring(0, 2).toUpperCase();

    return LanguageInfo(
      flag: '🌐',
      code: shortCode.isNotEmpty ? shortCode : 'SUB',
      name: input.trim().isNotEmpty ? input.trim() : 'Subtitle',
    );
  }
}
