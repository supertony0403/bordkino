#import "BKKeyboardView.h"

static NSString *const kBackspace = @"⌫";
static NSString *const kSpace = @"Leerzeichen";
static NSString *const kClear = @"Löschen";
static NSString *const kSubmit = @"Suchen";

@implementation BKKeyboardView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _text = @"";
        self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
        NSArray<NSArray<NSString *> *> *rows = @[
            @[@"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"0", @"ß"],
            @[@"q", @"w", @"e", @"r", @"t", @"z", @"u", @"i", @"o", @"p", @"ü"],
            @[@"a", @"s", @"d", @"f", @"g", @"h", @"j", @"k", @"l", @"ö", @"ä"],
            @[@"y", @"x", @"c", @"v", @"b", @"n", @"m", @"-", @".", kBackspace],
            @[kClear, kSpace, kSubmit],
        ];
        NSMutableArray *rowViews = [NSMutableArray new];
        for (NSArray<NSString *> *row in rows) {
            NSMutableArray *keys = [NSMutableArray new];
            for (NSString *key in row) [keys addObject:[self keyButton:key]];
            UIStackView *rowView = [[UIStackView alloc] initWithArrangedSubviews:keys];
            rowView.spacing = 5;
            rowView.distribution = row.count == 3 ? UIStackViewDistributionFill : UIStackViewDistributionFillEqually;
            if (row.count == 3) {
                UIButton *space = keys[1];
                [space.widthAnchor constraintGreaterThanOrEqualToAnchor:rowView.widthAnchor multiplier:0.5].active = YES;
            }
            [rowViews addObject:rowView];
        }
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:rowViews];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 5;
        stack.distribution = UIStackViewDistributionFillEqually;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:6],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-6],
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
        ]];
    }
    return self;
}

- (UIButton *)keyButton:(NSString *)key {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:key forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:key.length > 1 ? 18 : 24 weight:UIFontWeightSemibold];
    b.tintColor = UIColor.whiteColor;
    BOOL special = key.length > 1 || [key isEqualToString:kBackspace];
    b.backgroundColor = [key isEqualToString:kSubmit] ? [UIColor colorWithRed:0.96 green:0.62 blue:0.04 alpha:1]
                                                    : [UIColor colorWithWhite:special ? 0.22 : 0.3 alpha:1];
    if ([key isEqualToString:kSubmit]) b.tintColor = UIColor.blackColor;
    b.layer.cornerRadius = 7;
    b.accessibilityLabel = key;
    [b addTarget:self action:@selector(keyTapped:) forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)keyTapped:(UIButton *)sender {
    NSString *key = [sender titleForState:UIControlStateNormal];
    if ([key isEqualToString:kSubmit]) {
        NSString *query = [self.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (query.length && self.onSubmit) self.onSubmit(query);
        return;
    }
    if ([key isEqualToString:kBackspace]) {
        if (self.text.length) {
            NSRange last = [self.text rangeOfComposedCharacterSequenceAtIndex:self.text.length - 1];
            self.text = [self.text substringToIndex:last.location];
        }
    } else if ([key isEqualToString:kClear]) {
        self.text = @"";
    } else if ([key isEqualToString:kSpace]) {
        if (self.text.length && ![self.text hasSuffix:@" "]) self.text = [self.text stringByAppendingString:@" "];
    } else if (self.text.length < 80) {
        self.text = [self.text stringByAppendingString:key];
    }
    if (self.onText) self.onText(self.text);
}

@end
