/// Dial codes with ISO 3166-1 alpha-2 for flag emoji generation (avoids encoding issues).
class CountryDial {
  final String name;
  final String dial;
  final String code;

  const CountryDial(this.name, this.dial, this.code);

  String get flag {
    final c = code.toUpperCase();
    if (c.length != 2) return '';
    return String.fromCharCodes([
      0x1F1E6 + c.codeUnitAt(0) - 65,
      0x1F1E6 + c.codeUnitAt(1) - 65,
    ]);
  }

  Map<String, String> toMap() => {
        'name': name,
        'dial': dial,
        'code': code,
        'flag': flag,
      };
}

/// Returns flag emoji for an ISO country code (e.g. `TR` → 🇹🇷).
String countryFlagEmoji(String isoCode) {
  final c = isoCode.toUpperCase();
  if (c.length != 2) return '';
  return String.fromCharCodes([
    0x1F1E6 + c.codeUnitAt(0) - 65,
    0x1F1E6 + c.codeUnitAt(1) - 65,
  ]);
}

const List<CountryDial> kCountryDialList = [
  CountryDial('Afghanistan', '+93', 'AF'),
  CountryDial('Albania', '+355', 'AL'),
  CountryDial('Algeria', '+213', 'DZ'),
  CountryDial('Argentina', '+54', 'AR'),
  CountryDial('Australia', '+61', 'AU'),
  CountryDial('Austria', '+43', 'AT'),
  CountryDial('Bahrain', '+973', 'BH'),
  CountryDial('Bangladesh', '+880', 'BD'),
  CountryDial('Belgium', '+32', 'BE'),
  CountryDial('Brazil', '+55', 'BR'),
  CountryDial('Canada', '+1', 'CA'),
  CountryDial('Chile', '+56', 'CL'),
  CountryDial('China', '+86', 'CN'),
  CountryDial('Colombia', '+57', 'CO'),
  CountryDial('Croatia', '+385', 'HR'),
  CountryDial('Czech Republic', '+420', 'CZ'),
  CountryDial('Denmark', '+45', 'DK'),
  CountryDial('Egypt', '+20', 'EG'),
  CountryDial('Ethiopia', '+251', 'ET'),
  CountryDial('Finland', '+358', 'FI'),
  CountryDial('France', '+33', 'FR'),
  CountryDial('Germany', '+49', 'DE'),
  CountryDial('Ghana', '+233', 'GH'),
  CountryDial('Greece', '+30', 'GR'),
  CountryDial('Hungary', '+36', 'HU'),
  CountryDial('India', '+91', 'IN'),
  CountryDial('Indonesia', '+62', 'ID'),
  CountryDial('Iran', '+98', 'IR'),
  CountryDial('Iraq', '+964', 'IQ'),
  CountryDial('Ireland', '+353', 'IE'),
  CountryDial('Israel', '+972', 'IL'),
  CountryDial('Italy', '+39', 'IT'),
  CountryDial('Japan', '+81', 'JP'),
  CountryDial('Jordan', '+962', 'JO'),
  CountryDial('Kenya', '+254', 'KE'),
  CountryDial('Kuwait', '+965', 'KW'),
  CountryDial('Lebanon', '+961', 'LB'),
  CountryDial('Libya', '+218', 'LY'),
  CountryDial('Malaysia', '+60', 'MY'),
  CountryDial('Mexico', '+52', 'MX'),
  CountryDial('Morocco', '+212', 'MA'),
  CountryDial('Netherlands', '+31', 'NL'),
  CountryDial('New Zealand', '+64', 'NZ'),
  CountryDial('Nigeria', '+234', 'NG'),
  CountryDial('Norway', '+47', 'NO'),
  CountryDial('Oman', '+968', 'OM'),
  CountryDial('Pakistan', '+92', 'PK'),
  CountryDial('Palestine', '+970', 'PS'),
  CountryDial('Peru', '+51', 'PE'),
  CountryDial('Philippines', '+63', 'PH'),
  CountryDial('Poland', '+48', 'PL'),
  CountryDial('Portugal', '+351', 'PT'),
  CountryDial('Qatar', '+974', 'QA'),
  CountryDial('Romania', '+40', 'RO'),
  CountryDial('Russia', '+7', 'RU'),
  CountryDial('Saudi Arabia', '+966', 'SA'),
  CountryDial('Senegal', '+221', 'SN'),
  CountryDial('Serbia', '+381', 'RS'),
  CountryDial('Singapore', '+65', 'SG'),
  CountryDial('South Africa', '+27', 'ZA'),
  CountryDial('South Korea', '+82', 'KR'),
  CountryDial('Spain', '+34', 'ES'),
  CountryDial('Sudan', '+249', 'SD'),
  CountryDial('Sweden', '+46', 'SE'),
  CountryDial('Switzerland', '+41', 'CH'),
  CountryDial('Syria', '+963', 'SY'),
  CountryDial('Taiwan', '+886', 'TW'),
  CountryDial('Tanzania', '+255', 'TZ'),
  CountryDial('Thailand', '+66', 'TH'),
  CountryDial('Tunisia', '+216', 'TN'),
  CountryDial('Turkey', '+90', 'TR'),
  CountryDial('UAE', '+971', 'AE'),
  CountryDial('Uganda', '+256', 'UG'),
  CountryDial('Ukraine', '+380', 'UA'),
  CountryDial('United Kingdom', '+44', 'GB'),
  CountryDial('United States', '+1', 'US'),
  CountryDial('Venezuela', '+58', 'VE'),
  CountryDial('Vietnam', '+84', 'VN'),
  CountryDial('Yemen', '+967', 'YE'),
];

List<Map<String, String>> get kCountries =>
    kCountryDialList.map((c) => c.toMap()).toList();
