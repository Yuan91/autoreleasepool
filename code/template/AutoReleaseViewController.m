//
//  AutoReleaseViewController.m
//  template
//
//  Created by du on 2020/4/24.
//  Copyright © 2020 du. All rights reserved.
//

#import "AutoReleaseViewController.h"
#import "Person.h"
@interface AutoReleaseViewController ()

@property (nonatomic,strong) NSTimer *timer;

@end

@implementation AutoReleaseViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    //testCase1
//    NSLog(@"-----start----");
//
//    Person *p = [[[Person alloc]init] autorelease];
//    p.desc = @"testCase1";
//
//    NSLog(@"%s",__func__);
    
//    [self testCase0];
    
//    [self testCase2];
    
    [self testCase5];
}

- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    NSLog(@"%s",__func__);
}

- (void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    NSLog(@"%s",__func__);
}


- (void)testCase0{
    NSLog(@"-----start----");
    
    @autoreleasepool {
            Person *p = [[[Person alloc]init] autorelease];
            p.desc = @"testCase0";
    }
    
    NSLog(@"-----end----");
}

- (void)testCase2{
    self.timer = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(timeTest) userInfo:nil repeats:NO];
}



- (void)timeTest{
    NSLog(@"timer start");
    
    Person *p = [[[Person alloc]init] autorelease];
    p.desc = @"被定时器唤醒之后,创建的对象";
    
    NSLog(@"timer end");
}



- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    NSLog(@"---- touch 事件 开始了 ");
    Person *p = [[[Person alloc]init] autorelease];
    p.desc = @"点击唤醒之后,创建的对象";
    NSLog(@"---- touch 事件 结束了");
}


- (void)testCase5{
    NSLog(@"start");
    NSThread *thread = [[NSThread alloc]initWithBlock:^{
        NSLog(@"block start");
        Person *p = [[[Person alloc]init] autorelease];
        p.desc = @"子线程创建的autorelease对象";
        NSLog(@"block end");
    }];
    [thread start];
    NSLog(@"end");
}

@end
