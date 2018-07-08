//
//  RPVInstalledViewController.m
//  iOS
//
//  Created by Matt Clarke on 03/07/2018.
//  Copyright © 2018 Matt Clarke. All rights reserved.
//

#import "RPVInstalledViewController.h"
#import "RPVInstalledMainHeaderView.h"
#import "RPVResources.h"

#import "RPVApplication.h"
#import "RPVApplicationDatabase.h"
#import "RPVErrors.h"
#import "RPVNotificationManager.h"

#import "RPVInstalledCollectionViewCell.h"
#import "RPVInstalledTableViewCell.h"

// Fake data source stuff...
#define USE_FAKE_DATA 0

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
+ (instancetype)applicationProxyForIdentifier:(NSString*)arg1;
@end

@interface RPVInstalledViewController ()
// Views
@property (nonatomic, strong) UIScrollView *rootScrollView;

@property (nonatomic, strong) UIView *topBackgroundView;
@property (nonatomic, strong) CAGradientLayer *topBackgroundGradientLayer;

@property (nonatomic, strong) RPVInstalledMainHeaderView *mainHeaderView;
@property (nonatomic, strong) RPVInstalledSectionHeaderView *expiringSectionHeaderView;
@property (nonatomic, strong) UICollectionView *expiringCollectionView;
@property (nonatomic, strong) RPVInstalledSectionHeaderView *recentSectionHeaderView;
@property (nonatomic, strong) UITableView *recentTableView;
@property (nonatomic, strong) RPVInstalledSectionHeaderView *otherApplicationsSectionHeaderView;
@property (nonatomic, strong) UITableView *otherApplicationsTableView;

// Data sources
@property (nonatomic, strong) NSMutableArray *expiringSoonDataSource;
@property (nonatomic, strong) NSMutableArray *recentlySignedDataSource;
@property (nonatomic, strong) NSMutableArray *otherApplicationsDataSource;
@end

@implementation RPVInstalledViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    [self.expiringCollectionView registerClass:[RPVInstalledCollectionViewCell class] forCellWithReuseIdentifier:@"installed.cell"];
    [self.recentTableView registerClass:[RPVInstalledTableViewCell class] forCellReuseIdentifier:@"installed.cell"];
    
    [[RPVApplicationSigning sharedInstance] addSigningUpdatesObserver:self];
    
    // Reload data sources.
    [self _reloadDataSources];
    [self.recentSectionHeaderView requestNewButtonEnabledState];
    [self.expiringSectionHeaderView requestNewButtonEnabledState];
    [self.otherApplicationsSectionHeaderView requestNewButtonEnabledState];
    
    // Handle reloading data when the user has signed in.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_reloadDataForUserDidSignIn:) name:@"com.matchstic.reprovision.ios/userDidSignIn" object:nil];
    // Reload data when the resign threshold changes.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_reloadDataForUserDidSignIn:) name:@"com.matchstic.reprovision.ios/resigningThresholdDidChange" object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Set status bar colour
    [[UIApplication sharedApplication] setStatusBarStyle:[self preferredStatusBarStyle]];
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // Reset status bar colour
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)loadView {
    [super loadView];
    
    // Root view is a scrollview, sized to mainHeader + header + expiringcollection + header + tableview (no scrolling)
    self.rootScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.rootScrollView.delegate = self;
    self.rootScrollView.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1.0];
    if (@available(iOS 11.0, *)) {
        self.rootScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    [self.view addSubview:self.rootScrollView];
    
    // Background view for fancy UI
    self.topBackgroundView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.rootScrollView addSubview:self.topBackgroundView];
    
    self.topBackgroundGradientLayer = [CAGradientLayer layer];
    self.topBackgroundGradientLayer.frame = CGRectZero;
    
    UIColor *startColor = [UIColor colorWithRed:147.0/255.0 green:99.0/255.0 blue:207.0/255.0 alpha:1.0];
    UIColor *endColor = [UIColor colorWithRed:116.0/255.0 green:158.0/255.0 blue:201.0/255.0 alpha:1.0];
    self.topBackgroundGradientLayer.colors = @[(id)startColor.CGColor, (id)endColor.CGColor];
    self.topBackgroundGradientLayer.startPoint = CGPointMake(0.75, 0.75);
    self.topBackgroundGradientLayer.endPoint = CGPointMake(0.25, 0.25);
    
    [self.topBackgroundView.layer insertSublayer:self.topBackgroundGradientLayer atIndex:0];
    
    // Topmost header for date and title
    self.mainHeaderView = [[RPVInstalledMainHeaderView alloc] initWithFrame:CGRectZero];
    [self.mainHeaderView configureWithTitle:@"Installed"];
    [self.rootScrollView addSubview:self.mainHeaderView];
    
    // Section header for expiring apps
    self.expiringSectionHeaderView = [[RPVInstalledSectionHeaderView alloc] initWithFrame:CGRectZero];
    [self.expiringSectionHeaderView configureWithTitle:@"Expiring Soon" buttonLabel:@"SIGN" section:1 andDelegate:self];
    self.expiringSectionHeaderView.invertColours = YES;
    [self.rootScrollView addSubview:self.expiringSectionHeaderView];
    
    // Collectionview for expiring items
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = [self _collectionCellSize];
    layout.minimumLineSpacing = 15;
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    
    self.expiringCollectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.expiringCollectionView.backgroundColor = [UIColor clearColor];
    self.expiringCollectionView.delegate = self;
    self.expiringCollectionView.dataSource = self;
    [self.rootScrollView addSubview:self.expiringCollectionView];
    
    // Section header for recent items
    self.recentSectionHeaderView = [[RPVInstalledSectionHeaderView alloc] initWithFrame:CGRectZero];
    [self.recentSectionHeaderView configureWithTitle:@"Recently Signed" buttonLabel:@"SIGN" section:2 andDelegate:self];
    self.recentSectionHeaderView.invertColours = NO;
    [self.rootScrollView addSubview:self.recentSectionHeaderView];

    // Table View for recent items.
    self.recentTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.recentTableView.delegate = self;
    self.recentTableView.dataSource = self;
    self.recentTableView.scrollEnabled = NO;
    self.recentTableView.backgroundColor = [UIColor clearColor];
    self.recentTableView.separatorColor = [UIColor clearColor];
    [self.rootScrollView addSubview:self.recentTableView];
    
    // Section header for other apps
    self.otherApplicationsSectionHeaderView = [[RPVInstalledSectionHeaderView alloc] initWithFrame:CGRectZero];
    [self.otherApplicationsSectionHeaderView configureWithTitle:@"Other Applications" buttonLabel:@"ADD" section:3 andDelegate:self];
    self.otherApplicationsSectionHeaderView.invertColours = NO;
    [self.rootScrollView addSubview:self.otherApplicationsSectionHeaderView];
    
    // Table view for applications that are sideloaded on another Team ID.
    self.otherApplicationsTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.otherApplicationsTableView.delegate = self;
    self.otherApplicationsTableView.dataSource = self;
    self.otherApplicationsTableView.scrollEnabled = NO;
    self.otherApplicationsTableView.backgroundColor = [UIColor clearColor];
    self.otherApplicationsTableView.separatorColor = [UIColor clearColor];
    self.otherApplicationsTableView.allowsSelectionDuringEditing = YES;
    [self.rootScrollView addSubview:self.otherApplicationsTableView];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    CGFloat rootHeight = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? self.view.bounds.size.height : self.view.bounds.size.height - [(UITabBarController*)self.parentViewController tabBar].frame.size.height;
    self.rootScrollView.frame = CGRectMake(0, 0, self.view.bounds.size.width, rootHeight);
    
    CGFloat yOffset = [UIApplication sharedApplication].statusBarFrame.size.height + 10.0;
    CGFloat mainHeaderHeight = 80;
    CGFloat sectionHeaderHeight = 50;
    
    self.mainHeaderView.frame = CGRectMake(0, yOffset, self.view.bounds.size.width, mainHeaderHeight);
    
    yOffset += mainHeaderHeight + 5;
    
    self.expiringSectionHeaderView.frame = CGRectMake(0, yOffset, self.view.bounds.size.width, sectionHeaderHeight);
    
    yOffset += sectionHeaderHeight;
    
    if (self.expiringSoonDataSource.count == 0) {
        self.expiringCollectionView.frame = CGRectMake(0, yOffset, self.view.bounds.size.width, [self _tableViewCellHeight]);
        [self.expiringCollectionView.collectionViewLayout invalidateLayout];
    } else {
        self.expiringCollectionView.frame = CGRectMake(0, yOffset, self.view.bounds.size.width, [self _collectionCellSize].height + 30);
    }
    
    yOffset += self.expiringCollectionView.frame.size.height; // CollectionView's insets handle extra offsetting.
    
    // Top background view.
    self.topBackgroundView.frame = CGRectMake(0, 0, self.view.bounds.size.width, yOffset);
    self.topBackgroundGradientLayer.frame = self.topBackgroundView.bounds;
    
    yOffset += 5;
    
    self.recentSectionHeaderView.frame = CGRectMake(0, yOffset, self.view.bounds.size.width, sectionHeaderHeight);
    
    yOffset += sectionHeaderHeight + 5;
    
    // Table View's frame height is: insetTop + (n*itemheight) + insetBottom
    CGFloat height = [self tableView:self.recentTableView numberOfRowsInSection:0] * [self _tableViewCellHeight];
    self.recentTableView.frame = CGRectMake(0, yOffset, self.view.bounds.size.width, height);
    self.recentTableView.contentSize = CGSizeMake(self.view.bounds.size.width, height);
    
    yOffset += height + 15;
    
    // Other applications table view.
    self.otherApplicationsSectionHeaderView.frame = CGRectMake(0, yOffset, self.view.bounds.size.width, sectionHeaderHeight);
    
    yOffset += sectionHeaderHeight + 5;
    
    // Table View's frame height is: insetTop + (n*itemheight) + insetBottom
    CGFloat otherAppsHeight = [self tableView:self.otherApplicationsTableView numberOfRowsInSection:0] * [self _tableViewCellHeight];
    self.otherApplicationsTableView.frame = CGRectMake(0, yOffset, self.view.bounds.size.width, otherAppsHeight);
    self.otherApplicationsTableView.contentSize = CGSizeMake(self.view.bounds.size.width, otherAppsHeight);
    
    yOffset += otherAppsHeight + 15;
    
    // Finally, set content size for overall scrolling region.
    self.rootScrollView.contentSize = CGSizeMake(self.view.bounds.size.width, yOffset);
}

- (CGSize)_collectionCellSize {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? CGSizeMake(195, 183) : CGSizeMake(130, 122);
}

- (CGFloat)_tableViewCellHeight {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? 95 : 75;
}

// Status bar colouration
- (UIStatusBarStyle)preferredStatusBarStyle {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? UIStatusBarStyleDefault : UIStatusBarStyleLightContent;
}

//////////////////////////////////////////////////////////////////////////////////
// Data sources.
//////////////////////////////////////////////////////////////////////////////////

- (void)_reloadDataForUserDidSignIn:(id)sender {
    [self _reloadDataSources];
    
    // Reload header enabled states
    [self.recentSectionHeaderView requestNewButtonEnabledState];
    [self.expiringSectionHeaderView requestNewButtonEnabledState];
    [self.otherApplicationsSectionHeaderView requestNewButtonEnabledState];
}

- (void)_reloadDataSources {
    NSMutableArray *expiringSoon = [NSMutableArray array];
    NSMutableArray *recentlySigned = [NSMutableArray array];
    
    if (!USE_FAKE_DATA) {
        NSDate *now = [NSDate date];
        int thresholdForExpiration = [RPVResources thresholdForResigning]; // days
        
        NSDate *expirationDate = [now dateByAddingTimeInterval:60 * 60 * 24 * thresholdForExpiration];
        
        if (![[RPVApplicationDatabase sharedInstance] getApplicationsWithExpiryDateBefore:&expiringSoon andAfter:&recentlySigned date:expirationDate forTeamID:[RPVResources getTeamID]]) {
            
            // :(
        } else {
            self.expiringSoonDataSource = expiringSoon;
            self.recentlySignedDataSource = recentlySigned;
            
            // Reload the collection view and table view.
            [self.expiringCollectionView reloadData];
            [self.recentTableView reloadData];
        }
        
        // Also grab any other sideloaded applications
        self.otherApplicationsDataSource = [[[RPVApplicationDatabase sharedInstance] getAllSideloadedApplicationsNotMatchingTeamID:[RPVResources getTeamID]] mutableCopy];
        [self.otherApplicationsTableView reloadData];
    } else {
        [self _debugCreateFakeDataSources];
        
        // Reload the collection view and table view.
        [self.expiringCollectionView reloadData];
        [self.recentTableView reloadData];
        
        // Also grab any other sideloaded applications
        self.otherApplicationsDataSource = [[[RPVApplicationDatabase sharedInstance] getAllSideloadedApplicationsNotMatchingTeamID:[RPVResources getTeamID]] mutableCopy];
        [self.otherApplicationsTableView reloadData];
    }
    
    // Relayout for any changes!
    [self.view setNeedsLayout];
    
    // Set the sideloaded apps table to be editing if necessary.
    [self.otherApplicationsTableView setEditing:self.otherApplicationsDataSource.count > 0 animated:NO];
}

- (void)_debugCreateFakeDataSources {
    self.expiringSoonDataSource = [NSMutableArray array];
    self.recentlySignedDataSource = [NSMutableArray array];
    
    for (int i = 0; i < 5; i++) {
        LSApplicationProxy *proxy = [LSApplicationProxy applicationProxyForIdentifier:@"com.matchstic.reprovision.ios"];
        RPVApplication *application = [[RPVApplication alloc] initWithApplicationProxy:proxy];
        
        [self.recentlySignedDataSource addObject:application];
        [self.expiringSoonDataSource addObject:application];
    }
}

//////////////////////////////////////////////////////////////////////////////////
// Scroll View delegate methods.
//////////////////////////////////////////////////////////////////////////////////

// Gives the effect that the top area goes infinitely upwards
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat offsetY = scrollView.contentOffset.y;
    
    CGFloat totalTopAreaHeight = self.expiringCollectionView.frame.origin.y + self.expiringCollectionView.frame.size.height;
    
    if (offsetY < 0) {
        totalTopAreaHeight += fabs(offsetY);
        
        self.topBackgroundView.frame = CGRectMake(0, offsetY, self.view.frame.size.width, totalTopAreaHeight);
    } else {
        self.topBackgroundView.frame = CGRectMake(0, 0, self.view.frame.size.width, totalTopAreaHeight);
    }
    
    // Really, Apple? Animating frame change implcitly?
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    
    self.topBackgroundGradientLayer.frame = self.topBackgroundView.bounds;
    
    [CATransaction commit];
    
}

//////////////////////////////////////////////////////////////////////////////////
// Collection View delegate methods.
//////////////////////////////////////////////////////////////////////////////////

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    RPVInstalledCollectionViewCell *cell = (RPVInstalledCollectionViewCell*)[collectionView dequeueReusableCellWithReuseIdentifier:@"installed.cell" forIndexPath:indexPath];
    
    RPVApplication *application;
    NSString *fallbackString = @"";
    if (self.expiringSoonDataSource.count > 0)
        application = [self.expiringSoonDataSource objectAtIndex:indexPath.row];
    else
        fallbackString = @"No applications are expiring soon";
    
    [cell configureWithApplication:application fallbackDisplayName:fallbackString andExpiryDate:[application applicationExpiryDate]];
    
    return cell;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.expiringSoonDataSource.count > 0 ? self.expiringSoonDataSource.count : 1;
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout insetForSectionAtIndex:(NSInteger)section {
    return UIEdgeInsetsMake(0, 20, 15, 20);
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return self.expiringSoonDataSource.count > 0 ? [(UICollectionViewFlowLayout*)collectionViewLayout itemSize] : CGSizeMake(self.view.frame.size.width - 40, 50);
}


- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}

//////////////////////////////////////////////////////////////////////////////////
// Table View delegate methods.
//////////////////////////////////////////////////////////////////////////////////

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([tableView isEqual:self.recentTableView])
        return self.recentlySignedDataSource.count > 0 ? self.recentlySignedDataSource.count : 1;
    else
        return self.otherApplicationsDataSource.count > 0 ? self.otherApplicationsDataSource.count : 1;
}

- (UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RPVInstalledTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"installed.cell"];
    
    if (!cell) {
        cell = [[RPVInstalledTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"installed.cell"];
    }
    
    RPVApplication *application;
    NSString *fallbackString = @"";
    if ([tableView isEqual:self.recentTableView]) {
        if (self.recentlySignedDataSource.count > 0)
            application = [self.recentlySignedDataSource objectAtIndex:indexPath.row];
        else
            fallbackString = @"No applications are recently signed";
    } else {
        if (self.otherApplicationsDataSource.count > 0)
            application = [self.otherApplicationsDataSource objectAtIndex:indexPath.row];
        else
            fallbackString = @"No other sideloaded applications";
    }
    
    [cell configureWithApplication:application fallbackDisplayName:fallbackString andExpiryDate:[application applicationExpiryDate]];
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self _tableViewCellHeight];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

// We provide editing only for the other applications table.

- (BOOL)tableView:(UITableView*)tableView canEditRowAtIndexPath:(NSIndexPath*)arg2 {
    return [tableView isEqual:self.otherApplicationsTableView];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [tableView isEqual:self.otherApplicationsTableView] ? UITableViewCellEditingStyleInsert : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Can only be from the other table view.
        NSString *bundleIdentifier = [self.otherApplicationsDataSource objectAtIndex:indexPath.row];
        
        // Start signing this one app.
        [[RPVApplicationSigning sharedInstance] resignSpecificApplications:@[bundleIdentifier]
                                                                withTeamID:[RPVResources getTeamID]
                                                                  username:[RPVResources getUsername]
                                                                  password:[RPVResources getPassword]];
    }
}

//////////////////////////////////////////////////////////////////////////////////
// Application Signing delegate methods.
//////////////////////////////////////////////////////////////////////////////////

- (void)applicationSigningDidStart {}

- (void)applicationSigningUpdateProgress:(int)progress forBundleIdentifier:(NSString *)bundleIdentifier {
    if (progress == 100) {
        // Great success! Now we can move items around!
        dispatch_async(dispatch_get_main_queue(), ^{
        
        int oldDataSource = 0;
        RPVApplication *application;
        // Check expiring
        for (RPVApplication *app in self.expiringSoonDataSource) {
            if ([app.bundleIdentifier isEqualToString:bundleIdentifier]) {
                oldDataSource = 1;
                application = app;
                break;
            }
        }
        // Check recents
        for (RPVApplication *app in self.recentlySignedDataSource) {
            if ([app.bundleIdentifier isEqualToString:bundleIdentifier]) {
                oldDataSource = 2;
                application = app;
                break;
            }
        }
        // Check others
        for (RPVApplication *app in self.otherApplicationsDataSource) {
            if ([app.bundleIdentifier isEqualToString:bundleIdentifier]) {
                oldDataSource = 3;
                application = app;
                break;
            }
        }
        
        // Move from the old data source to number 2.
        if (oldDataSource == 1) {
            [self.expiringCollectionView performBatchUpdates:^{
                int index = (int)[self.expiringSoonDataSource indexOfObject:application];
                
                // Remove items from data source.
                [self.expiringSoonDataSource removeObjectAtIndex:index];
                
                // And from collection view, maybe...
                if (self.expiringSoonDataSource.count == 0) {
                    // Reload!
                    [self.expiringCollectionView reloadData];
                } else {
                    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
                    [self.expiringCollectionView deleteItemsAtIndexPaths:[NSArray arrayWithObject:indexPath]];
                }
            } completion:^(BOOL finished) {
                
            }];
        } else if (oldDataSource == 2) {
            // Effectively this will be a re-order, but oh well.
            // Newest items go at the bottom.
            [self.recentTableView beginUpdates];
            
            int index = (int)[self.recentlySignedDataSource indexOfObject:application];
            [self.recentlySignedDataSource removeObjectAtIndex:index];
            
            // Delete the row from the table, maybe...
            
            if (self.recentlySignedDataSource.count == 0) {
                // Reload the table to show the "no apps" thing
                
                [self.recentTableView reloadData];
            } else {
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
                
                [self.recentTableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            }
            
            [self.recentTableView endUpdates];
        } else if (oldDataSource == 3) {
            [self.otherApplicationsTableView beginUpdates];
            
            int index = (int)[self.otherApplicationsDataSource indexOfObject:application];
            [self.otherApplicationsDataSource removeObjectAtIndex:index];
            
            // Delete the row from the table, maybe...
            if (self.otherApplicationsDataSource.count == 0) {
                // Reload the table to show the "no apps" label
                [self.otherApplicationsTableView reloadData];
            } else {
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
                
                [self.otherApplicationsTableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            }
            
            [self.otherApplicationsTableView endUpdates];
        }
            
        // Now that we've removed the old application, create a new object for it to handle changes
        // in the bundle URL of the application on-disk.
        application = [[RPVApplicationDatabase sharedInstance] getApplicationWithBundleIdentifier:[application bundleIdentifier]];
        
        [self.recentTableView beginUpdates];
        
        // And add to source 2.
        [self.recentlySignedDataSource addObject:application];
        int index = (int)[self.recentlySignedDataSource indexOfObject:application];
        
        if (self.recentlySignedDataSource.count == 1) {
            // Reload the table instead to hide the no apps label
            [self.recentTableView reloadData];
        } else {
            // Add the row to the table
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
            
            [self.recentTableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        }
        
        [self.recentTableView endUpdates];
        
        // We now need to relayout everything!
        [self.view setNeedsLayout];
            
        });
    }
}

- (void)applicationSigningDidEncounterError:(NSError *)error forBundleIdentifier:(NSString *)bundleIdentifier {}

- (void)applicationSigningCompleteWithError:(NSError *)error {}

- (void)startApplicationSigningForSection:(NSInteger)section {
    NSString *startAlertString = @"";
    switch (section) {
        case 1:
            startAlertString = @"Starting signing for applications expiring soon";
            break;
        case 2:
            startAlertString = @"Starting signing for all applications";
            break;
        case 3:
            startAlertString = @"Starting signing for other sideloaded applications";
            break;
            
        default:
            break;
    }
    
    [[RPVNotificationManager sharedInstance] sendNotificationWithTitle:@"DEBUG" body:startAlertString isDebugMessage:YES andNotificationID:nil];
    
    if (section == 3) {
        // Sign all other sideloaded applications to this Team ID.
        [[RPVApplicationSigning sharedInstance] resignSpecificApplications:self.otherApplicationsDataSource
                                                                withTeamID:[RPVResources getTeamID]
                                                                  username:[RPVResources getUsername]
                                                                  password:[RPVResources getPassword]];
    } else {
        [[RPVApplicationSigning sharedInstance] resignApplications:(section == 1)
                                            thresholdForExpiration:[RPVResources thresholdForResigning]
                                                        withTeamID:[RPVResources getTeamID]
                                                          username:[RPVResources getUsername]
                                                          password:[RPVResources getPassword]];
    }
}

//////////////////////////////////////////////////////////////////////////////////
// Header View delegate methods.
//////////////////////////////////////////////////////////////////////////////////

- (void)didRecieveHeaderButtonInputWithSection:(NSInteger)section {
    // Handle button input!
    NSLog(@"Got input: %d", (int)section);
    [self startApplicationSigningForSection:section];
}

- (BOOL)isButtonEnabledForSection:(NSInteger)section {
    switch (section) {
        case 1:
            return self.expiringSoonDataSource.count > 0;
        case 2:
            return self.recentlySignedDataSource.count > 0;
        case 3:
            return self.otherApplicationsDataSource.count > 0;
        default:
            return NO;
    }
}

@end