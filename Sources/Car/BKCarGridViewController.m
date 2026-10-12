#import "BKCarGridViewController.h"
#import "BKPlayer.h"
#import "BKLibrary.h"
#import "BKImageLoader.h"

@interface BKCarCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *thumb;
@property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) UILabel *detail;
@property (nonatomic, strong) UILabel *badge;
@end

@implementation BKCarCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _thumb = [UIImageView new];
        _thumb.contentMode = UIViewContentModeScaleAspectFill;
        _thumb.clipsToBounds = YES;
        _thumb.layer.cornerRadius = 10;
        _thumb.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
        _badge = [UILabel new];
        _badge.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightBold];
        _badge.textColor = UIColor.whiteColor;
        _badge.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
        _badge.layer.cornerRadius = 5;
        _badge.clipsToBounds = YES;
        _badge.textAlignment = NSTextAlignmentCenter;
        _title = [UILabel new];
        _title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        _title.textColor = UIColor.whiteColor;
        _title.numberOfLines = 2;
        _detail = [UILabel new];
        _detail.font = [UIFont systemFontOfSize:14];
        _detail.textColor = UIColor.lightGrayColor;
        for (UIView *v in @[_thumb, _badge, _title, _detail]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
        [NSLayoutConstraint activateConstraints:@[
            [_thumb.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_thumb.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_thumb.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_thumb.heightAnchor constraintEqualToAnchor:_thumb.widthAnchor multiplier:9.0 / 16.0],
            [_badge.trailingAnchor constraintEqualToAnchor:_thumb.trailingAnchor constant:-6],
            [_badge.bottomAnchor constraintEqualToAnchor:_thumb.bottomAnchor constant:-6],
            [_badge.heightAnchor constraintEqualToConstant:22],
            [_badge.widthAnchor constraintGreaterThanOrEqualToConstant:44],
            [_title.topAnchor constraintEqualToAnchor:_thumb.bottomAnchor constant:6],
            [_title.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_title.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_detail.topAnchor constraintEqualToAnchor:_title.bottomAnchor constant:2],
            [_detail.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_detail.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        ]];
    }
    return self;
}
@end

@interface BKCarGridViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@end

@implementation BKCarGridViewController {
    UICollectionView *_collection;
    UILabel *_emptyLabel;
    NSMutableArray<BKVideo *> *_items;
    NSString *_next;
    BOOL _loading;
    NSUInteger _generation;
    NSString *_error;
}

- (instancetype)initWithLoader:(BKVideoListLoader)loader emptyText:(NSString *)emptyText {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _loader = [loader copy];
        _emptyText = [emptyText copy];
        _items = [NSMutableArray new];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.07 blue:0.13 alpha:1];
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumInteritemSpacing = 14;
    layout.minimumLineSpacing = 18;
    layout.sectionInset = UIEdgeInsetsMake(12, 12, 24, 12);
    _collection = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    _collection.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _collection.backgroundColor = UIColor.clearColor;
    _collection.dataSource = self;
    _collection.delegate = self;
    [_collection registerClass:BKCarCell.class forCellWithReuseIdentifier:@"cell"];
    [self.view addSubview:_collection];

    _emptyLabel = [UILabel new];
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.textColor = UIColor.lightGrayColor;
    _emptyLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightMedium];
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],
    ]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryChanged) name:BKLibraryDidChangeNotification object:nil];
    [self reload];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)libraryChanged {
    if (self.reloadsOnLibraryChange) [self reload];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [_collection.collectionViewLayout invalidateLayout];
}

- (void)reload {
    if (!self.isViewLoaded) return;
    _generation++;
    [_items removeAllObjects];
    _next = nil;
    _error = nil;
    _loading = NO;
    [_collection reloadData];
    [self loadPage:nil];
}

- (void)loadPage:(NSString *)continuation {
    if (!self.loader || _loading) { [self updateEmpty]; return; }
    _loading = YES;
    [self updateEmpty];
    NSUInteger generation = _generation;
    __weak BKCarGridViewController *weakSelf = self;
    self.loader(continuation, ^(NSArray<BKVideo *> *items, NSString *next, NSError *error) {
        BKCarGridViewController *strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf->_generation) return;
        strongSelf->_loading = NO;
        if (error) {
            strongSelf->_error = error.localizedDescription;
        } else {
            NSMutableSet *known = [NSMutableSet setWithArray:[strongSelf->_items valueForKey:@"identifier"]];
            for (BKVideo *v in items) {
                if (![known containsObject:v.identifier]) { [known addObject:v.identifier]; [strongSelf->_items addObject:v]; }
            }
            strongSelf->_next = items.count ? next : nil;
        }
        [strongSelf->_collection reloadData];
        [strongSelf updateEmpty];
    });
}

- (void)updateEmpty {
    _emptyLabel.hidden = _items.count > 0;
    _emptyLabel.text = _loading ? @"Lädt …" : (_error ?: self.emptyText);
}

#pragma mark Collection

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return _items.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    BKCarCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"cell" forIndexPath:indexPath];
    BKVideo *v = _items[indexPath.item];
    cell.title.text = v.title;
    cell.detail.text = v.channel;
    cell.badge.text = v.durationText.length ? [NSString stringWithFormat:@" %@ ", v.durationText] : nil;
    cell.badge.hidden = v.durationText.length == 0;
    cell.badge.backgroundColor = v.isLive ? UIColor.systemRedColor : [UIColor colorWithWhite:0 alpha:0.75];
    [BKImageLoader loadURL:v.thumbnailURL into:cell.thumb];
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewFlowLayout *flow = (UICollectionViewFlowLayout *)layout;
    CGFloat available = collectionView.bounds.size.width - flow.sectionInset.left - flow.sectionInset.right;
    NSInteger columns = MAX(2, (NSInteger)floor((available + flow.minimumInteritemSpacing) / (240 + flow.minimumInteritemSpacing)));
    CGFloat width = floor((available - flow.minimumInteritemSpacing * (columns - 1)) / columns);
    return CGSizeMake(width, width * 9.0 / 16.0 + 70);
}

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    if (_next && !_loading && indexPath.item >= (NSInteger)_items.count - 4) [self loadPage:_next];
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [[BKPlayer shared] playVideo:_items[indexPath.item]];
}

@end
