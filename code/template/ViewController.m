//
//  ViewController.m
//  template
//
//  Created by du on 2020/4/12.
//  Copyright © 2020 du. All rights reserved.
//

#import "ViewController.h"

#import "AutoReleaseViewController.h"
@interface ViewController ()<UITableViewDelegate,UITableViewDataSource>

@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (nonatomic,copy) NSArray *array;

@end



@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.array = @[
                   @"测试autoRelease对象释放时机"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    

//    [self addRlo];   
}

- (void)addRlo{
CFRunLoopObserverRef rlo = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, kCFRunLoopAllActivities, YES, 0, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
       switch (activity) {
           case kCFRunLoopEntry:
               NSLog(@"进入runloop");
               break;
           
               case kCFRunLoopBeforeTimers:
               NSLog(@"处理timers之前");
               break;
               
               case kCFRunLoopBeforeSources:
               NSLog(@"处理source之前");
               break;
               
               //睡眠之前,等待timer或source唤醒
               case kCFRunLoopBeforeWaiting:
               NSLog(@"------->睡眠之前");
               break;
               
               //代表一个时间段,runloop被唤醒之后,处理唤醒事件之前的一段时间.
               case kCFRunLoopAfterWaiting:
               NSLog(@"------->唤醒之后");
               break;
               
               case kCFRunLoopExit:
               NSLog(@"退出了runloop");
               break;
               
           default:
               break;
       }
   });
   
   CFRunLoopRef rl = CFRunLoopGetCurrent();
   
   CFRunLoopAddObserver(rl, rlo, kCFRunLoopDefaultMode);
   
   CFRelease(rlo);
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    return  self.array.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    cell.textLabel.text = self.array[indexPath.row];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    UIViewController *vc = nil;
    if (indexPath.row == 0) {
        vc = [AutoReleaseViewController new];
    }
    [self.navigationController pushViewController:vc animated:YES];
}


@end
