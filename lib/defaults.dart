/// Starting categories and auto-category keywords. All editable in the app.

const palette = <int>[
  0xFF0D6B5B, 0xFFB4612B, 0xFF3A6EA5, 0xFF8E5BA8, 0xFFC0912B, 0xFF5B8C3A,
  0xFFB3322F, 0xFF2F8F8F, 0xFF7A6A58, 0xFFD06C8C, 0xFF4E5BA6, 0xFF6F7F2E,
];

class SeedCategory {
  final String name;
  final String kind;
  final String grp;
  const SeedCategory(this.name, this.kind, this.grp);
}

const seedCategories = <SeedCategory>[
  SeedCategory('Housing', 'expense', 'need'),
  SeedCategory('Utilities', 'expense', 'need'),
  SeedCategory('Groceries', 'expense', 'need'),
  SeedCategory('Transport', 'expense', 'need'),
  SeedCategory('Health', 'expense', 'need'),
  SeedCategory('Education', 'expense', 'need'),
  SeedCategory('Family', 'expense', 'need'),
  SeedCategory('Dining', 'expense', 'want'),
  SeedCategory('Shopping', 'expense', 'want'),
  SeedCategory('Subscriptions', 'expense', 'want'),
  SeedCategory('Entertainment', 'expense', 'want'),
  SeedCategory('Travel', 'expense', 'want'),
  SeedCategory('Personal care', 'expense', 'want'),
  SeedCategory('Charity', 'expense', 'want'),
  SeedCategory('Other', 'expense', 'want'),
  SeedCategory('Savings & investments', 'expense', 'save'),
  SeedCategory('Salary', 'income', 'income'),
  SeedCategory('Housing allowance', 'income', 'income'),
  SeedCategory('Bonus', 'income', 'income'),
  SeedCategory('Consulting / freelance', 'income', 'income'),
  SeedCategory('Investment income', 'income', 'income'),
  SeedCategory('Refunds', 'income', 'income'),
  SeedCategory('Other income', 'income', 'income'),
];

/// keyword (lower-case, matched inside merchant name or SMS text) -> category name
const seedRules = <String, String>{
  'lulu': 'Groceries', 'othaim': 'Groceries', 'panda': 'Groceries', 'danube': 'Groceries',
  'tamimi': 'Groceries', 'carrefour': 'Groceries', 'nesto': 'Groceries', 'farm superstore': 'Groceries',
  'fuel': 'Transport', 'sasco': 'Transport', 'aldrees': 'Transport', 'petromin': 'Transport',
  'naft': 'Transport', 'tameeni': 'Transport', 'careem': 'Transport', 'uber': 'Transport',
  'hungerstation': 'Dining', 'jahez': 'Dining', 'keeta': 'Dining', 'kitopi': 'Dining', 'mrsool': 'Dining',
  'toyou': 'Dining', 'starbucks': 'Dining', 'dr cafe': 'Dining', 'barn': 'Dining', 'kudu': 'Dining',
  'albaik': 'Dining', 'romansia': 'Dining', 'romansiah': 'Dining', 'mcdonald': 'Dining', 'cafe': 'Dining',
  'restaura': 'Dining', 'burger': 'Dining',
  'stc': 'Utilities', 'mobily': 'Utilities', 'zain': 'Utilities', 'sadad': 'Utilities', 'سداد': 'Utilities',
  'electricity': 'Utilities', 'الكهرباء': 'Utilities',
  'aldawaa': 'Health', 'nahdi': 'Health', 'hospital': 'Health', 'clinic': 'Health', 'pharmacy': 'Health',
  'صيدلية': 'Health', 'mouwasat': 'Health',
  'shein': 'Shopping', 'amazon': 'Shopping', 'noon': 'Shopping', 'centrepoint': 'Shopping',
  'next': 'Shopping', 'landmark': 'Shopping', 'ikea': 'Shopping', 'extra': 'Shopping', 'jarir': 'Shopping',
  'tabby': 'Shopping', 'tamara': 'Shopping', 'perfume': 'Shopping',
  'netflix': 'Subscriptions', 'shahid': 'Subscriptions', 'spotify': 'Subscriptions',
  'apple.com': 'Subscriptions', 'google': 'Subscriptions', 'anghami': 'Subscriptions',
  'ehsan': 'Charity', 'احسان': 'Charity', 'إحسان': 'Charity',
  'salon': 'Personal care', 'barber': 'Personal care',
  'saudia': 'Travel', 'flynas': 'Travel', 'flyadeal': 'Travel', 'booking.com': 'Travel',
  'salary': 'Salary', 'راتب': 'Salary', 'مرتب': 'Salary',
  // Egypt and the Gulf
  'spinneys': 'Groceries', 'hyperone': 'Groceries', 'hyper one': 'Groceries', 'kazyon': 'Groceries',
  'metro market': 'Groceries', 'breadfast': 'Groceries', 'instashop': 'Groceries', 'sultan center': 'Groceries',
  'talabat': 'Dining', 'deliveroo': 'Dining', 'zomato': 'Dining', 'elmenus': 'Dining',
  'swvl': 'Transport', 'indrive': 'Transport', 'didi': 'Transport', 'salik': 'Transport', 'enoc': 'Transport',
  'adnoc': 'Transport', 'woqod': 'Transport',
  'vodafone': 'Utilities', 'orange': 'Utilities', 'etisalat': 'Utilities', 'we internet': 'Utilities',
  'fawry': 'Utilities', 'dewa': 'Utilities', 'ooredoo': 'Utilities',
  'ezaby': 'Health', 'العزبي': 'Health', 'seif pharm': 'Health',
  'b.tech': 'Shopping', 'raya': 'Shopping', 'sharaf dg': 'Shopping',
};
