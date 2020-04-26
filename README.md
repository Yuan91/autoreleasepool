# autoreleasepool 探究

## 原理探究

自动释放池在释放的时候,会对加入其中的对象发送`release`消息,从而达到延迟对象释放的目的.那么自动释放池在底层究竟对应怎样的数据结构?自动释放释放池又是怎样创建?何时销毁呢?下面通过源码,一探究竟.

```
@autoreleasepool {
    Person *person = [[Person alloc] init] ;
}
```
通过`Clang`查看编译后的源码
```
void *atautoreleasepoolobj = objc_autoreleasePoolPush();

Person *person = [[Person alloc] init] ;

objc_autoreleasePoolPop(atautoreleasepoolobj);
```
可以看到`@autoreleasepool`包裹的代码编译之后,被两个C语言函数`objc_autoreleasePoolPush`和`objc_autoreleasePoolPop`来包裹.我们通过`objc-runtime`源码来进一步探寻这两个函数的实现.通过[这里](https://github.com/RetVal/objc-runtime)你可以下载一份可以编译调试的runtime源码.

查看源码
```
void *
objc_autoreleasePoolPush(void)
{
    return AutoreleasePoolPage::push();
}

NEVER_INLINE
void
objc_autoreleasePoolPop(void *ctxt)
{
    AutoreleasePoolPage::pop(ctxt);
}
```
现在已经较为清晰了,自动释放池对应这个`AutoreleasePoolPage`这个类,上面的两个C函数分别对应`AutoreleasePoolPage`的`push`和`pop`方法.

### push 函数
```
static inline void *push() 
{
    id *dest;
    if (slowpath(DebugPoolAllocation)) {
        // Each autorelease pool starts on a new pool page.
        dest = autoreleaseNewPage(POOL_BOUNDARY);
    } else {
        //添加一个哨兵对象到自动释放池
        dest = autoreleaseFast(POOL_BOUNDARY);
    }
    ...
    return dest;
}

//向自动释放池中添加对象
static inline id *autoreleaseFast(id obj)
{
    //获取hotPage:当前正在使用的Page
    AutoreleasePoolPage *page = hotPage();
    //如果有page 并且 page没有被占满
    if (page && !page->full()) { 
        //添加一个对象
        return page->add(obj);
    } else if (page) { 
        //添加一个对象
        return autoreleaseFullPage(obj, page);
    } else { //如果没有page,则创建一个page
        return autoreleaseNoPage(obj);
    }
}

//创建一个新的page,并将当前page->child指向新的page,将对象添加进去
id *autoreleaseFullPage(id obj, AutoreleasePoolPage *page)
{
    ...
    do {
        if (page->child) page = page->child;
        else page = new AutoreleasePoolPage(page);
    } while (page->full());

    setHotPage(page);
    return page->add(obj);
}

//创建一个新的page
id *autoreleaseNoPage(id obj)
{
    ...
    AutoreleasePoolPage *page = new AutoreleasePoolPage(nil);
    setHotPage(page);
    ...
    // Push the requested object or pool.
    return page->add(obj);
}
```
通过对push函数的分析可知:
* 每次调用push的时候,会创建一个向当前Page添加一个哨兵对象(查看源码发现它的值为`nil`),并返回这个它的地址

* 如果当前没有Page或者Page满了的时候,会创建新的Page.并把原Page的child指针指向新创建的Page

### pop 函数

```
//查看源码发现pop函数最终会调用 releaseUntil
//调用顺序为pop->popPage->releaseUntil

//stop 的值即为最初push时返回的哨兵对象的地址.
void releaseUntil(id *stop) 
{    
    //循环依次向autorelease对象发送release消息
    while (this->next != stop) {
        //AutoreleasePoolPage 有cold和hot之分.hot是当前正在使用的,cold是没有使用的
        //获取当前正在使用的
        AutoreleasePoolPage *page = hotPage();

        //如果为空,通过parent指针指向它的父节点,并将父节点置为当前使用的page
        while (page->empty()) {
            page = page->parent;
            setHotPage(page);
        }

        page->unprotect();
        //获取当前Page next指针的上一个元素
        id obj = *--page->next;
        memset((void*)page->next, SCRIBBLE, sizeof(*page->next));
        page->protect();

        //从next的上一个元素开始,向上查找只要不是哨兵对象,就向其发送release消息
        if (obj != POOL_BOUNDARY) {
            objc_release(obj);
        }
    }

    setHotPage(this);
}
```
从源代码发现pop函数的作用:
* 从当前page最新加入的对象开始,直到哨兵对象为止,依次发送release消息

* 上面这个过程可以跨页(AutoreleasePoolPage)

### autorelease 函数
```
Person *p3 = [[[Person alloc]init] autorelease];
```
MRC下可以通过调用`autorelease`,将对象加入到自动释放池中,其源码如下
```
static inline id autorelease(id obj)
{
    ASSERT(obj);
    ASSERT(!obj->isTaggedPointer());
    //调用autoreleaseFast,添加到自动释放池中
    id *dest __unused = autoreleaseFast(obj);
    ASSERT(!dest  ||  dest == EMPTY_POOL_PLACEHOLDER  ||  *dest == obj);
    return obj;
}

//上面已经分析过.
static inline id *autoreleaseFast(id obj)
{
    AutoreleasePoolPage *page = hotPage();
    if (page && !page->full()) {
        return page->add(obj);
    } else if (page) {
        return autoreleaseFullPage(obj, page);
    } else {
        return autoreleaseNoPage(obj);
    }
}
```

## AutoreleasePoolPage 数据结构及原理
经过上面的源码分析,我们已经对`AutoreleasePoolPage`有了大致的了解,下面对其做一个详细的总结

### 数据结构
```
//关键的数据结构
AutoreleasePoolPage
{
	magic_t const magic;
	__unsafe_unretained id *next;
	pthread_t const thread;
	AutoreleasePoolPage * const parent;
	AutoreleasePoolPage *child;
	uint32_t const depth;
	uint32_t hiwat;
}
```
示意图
![avatar](https://s1.ax1x.com/2020/04/26/Jg8Vwn.png)

AutoreleasePoolPage工作原理总结
* 每个`AutoreleasePoolPage`对象有4096字节的存储空间,除了存放它自己的成员变量外,剩下的空间用来存储`autorelease`对象

* `AutoreleasePoolPage`并不是一个单独的结构,而是有若干个`AutoreleasePoolPage`以**双向链表**的形式构成,分别对应其`parent`和`child`指针

* 调用`objc_autoreleasePoolPush`会创建`AutoreleasePoolPage`,同时向当前Page添加一个哨兵对象,并返回这个它的地址

* 调用`objc_autoreleasePoolPop`会从当前page next指针的上一个元素开始查找,直到最近一个哨兵对象,依次向这个范围中的对象发送`release`消息

* next指针作为游标,指向栈顶最新add进来的autorelease对象的下一个位置


## 程序中常见的四种autoreleasepool 
通过以上的分析,对于`autoreleasepool`的原理和作用已经有了一个清晰的认识.下面来分析一下,程序中遇到的四种`autoreleasepool`的作用以及释放时机.

研究方式:
通过`-fno-objc-arc`将`ViewController`设置为`MRC`管理的方式;
对于自定义的`Person`类,创建出来的对象添加`autorelease`标识,重写`Person`类的`dealloc`方法观察其释放时机;
给主线程runloop添加observer,观察其状态切换.

### 通过@autoreleasepool手动创建
```
- (void)testCase0{
    NSLog(@"-----start----");
    
    @autoreleasepool {
            Person *p = [[[Person alloc]init] autorelease];
            p.desc = @"testCase0";
    }
    
    NSLog(@"-----end----");
}

打印数据:
-----start----
Person:testCase0 dealloc
-----end----
```
可以看到`autorelease`描述的对象,在自动释放池结束的时候就释放了,并不会等到其方法作用域结束的时候才释放.

这与我们上面的分析,是一致的.`@autoreleasepool{}`结束的时候,会调用`objc_autoreleasePoolPop`进行一次清空操作.

### 主线程中隐式创建的autoreleasepool
下面来看一段代码,`viewDidLoad`中创建`autorelease`的Person对象,这里面并没有创建自动释放池,那么用`autorelease`描述`Person`对象到底有什么作用?`Person`对象又是什么时候释放的呢?
```
- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    NSLog(@"-----start----");

    Person *p = [[[Person alloc]init] autorelease];
    p.desc = @"testCase1";

    NSLog(@"%s",__func__);
    
//    [self testCase0];
}

- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    NSLog(@"%s",__func__);
}

- (void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    NSLog(@"%s",__func__);
}

/**
打印数据
------->睡眠之前
-----start----
[AutoReleaseViewController viewDidLoad]
[AutoReleaseViewController viewWillAppear:]
Person:testCase1 dealloc
------->唤醒之后
*/
```
可以看到`Person`对象的存在,超过了它的作用域`viewDidLoad`,并且是在`viewWillAppear`之后才释放的,这是为什么呢?
解答这个问题,需要一些`runloop`相关的知识.在应用启动之后,我们打印主线程的`runloop`可以看到以下内容.
```
observers = (
    "<CFRunLoopObserver 0x6000037a4a00 [0x7fff805eff70]>
    {valid = Yes, activities = 0x1, repeats = Yes, order = -2147483647, callout = _wrapRunLoopWithAutoreleasePoolHandler (0x7fff47571f14), context = <CFArray 0x6000008fc330 [0x7fff805eff70]>
    ",
    
    "<CFRunLoopObserver 0x6000037a48c0 [0x7fff805eff70]>
    {valid = Yes, activities = 0xa0, repeats = Yes, order = 2147483647, callout = _wrapRunLoopWithAutoreleasePoolHandler (0x7fff47571f14), context = <CFArray 0x6000008fc330 [0x7fff805eff70]>
    "
)
```
通过YYKit作者的总结我们知道:
 >应用启动后,runloop注册了两个Observer,这两个观察者的callback都是`_wrapRunLoopWithAutoreleasePoolHandler`

>第一个观察者监测的事件是:即将进入runloop(kCFRunLoopEntry),此时会调用`objc_autoreleasePoolPush`创建自动释放池,这个活动优先级最高,确保在进入runloop的时候,自动释放池已经创建好了.

>第二个观察者监测了两个事件:kCFRunLoopBeforeWaiting和kCFRunLoopExit,此时会调用`_objc_autoreleasePoolPop()` 和`_objc_autoreleasePoolPush()` 释放旧池创建新池.它的优先级是最低的,确保释放自动池在其他回调之后.

想要详细探究,可以通过符号断点`_wrapRunLoopWithAutoreleasePoolHandler`来查看,这里不细说.

通过上面对`runloop`的了解,可以知道,当主线程`runloop`处于`kCFRunLoopEntry`的时候,会创建新的自动释放池,而当`runloop`处于休眠和`exit`的时候,会释放旧池创建新池.

那么上面的问题就好解决了,`autorelease`描述的对象,是被添加到当前`runloop`中系统自动创建的`autoreleasePool`中了,这个系统隐式创建的自动释放池是在空闲的时候才会释放的,所以它的生命周期存活到了`viewWillAppear`之后.

**但是事实真的是这样的吗?系统的自动释放池总是在`kCFRunLoopBeforeWaiting和kCFRunLoopExit`才释放的吗**

带着这样的疑问,我们通过Timer和点击事件唤醒runloop,并在Person对象的dealloc中打上断点.
#### Timer 分析
```
- (void)testCase2{
    self.timer = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(timeTest) userInfo:nil repeats:NO];
}


- (void)timeTest{
    NSLog(@"timer start");
    
    Person *p = [[[Person alloc]init] autorelease];
    p.desc = @"被定时器唤醒之后,创建的对象";
    
    NSLog(@"timer end");
}

/**
打印数据

 ------->唤醒之后

 timer start
 timer end
 Person:被定时器唤醒之后,创建的对象 dealloc

 处理timers之前

 处理source之前
 ------->睡眠之前
*/
```

可以看到当定时器的时间点到了之后,runloop被唤醒执行timer事件. 事件处理完之后,`autorelease`对象即释放了,并没有等到我们上面所说的`kCFRunLoopBeforeWaiting`(睡眠之前)才释放.

所以我们猜想**执行完Timer事件之后,也会调用一次`objc_autoreleasePoolPop`**

接下来,我们在`dealloc`打上断点,通过`thread backtrace`查看一下调用栈
![avatar](https://s1.ax1x.com/2020/04/26/JReSuq.png)
结果清晰明了,正如我们所料,在执行完Timer事件后,直接调用了一次`objc_autoreleasePoolPop`函数,而并没有等到`runloop`处于空闲状态才释放

#### Touch 事件
```
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    NSLog(@"---- touch 事件 开始了 ");
    Person *p = [[[Person alloc]init] autorelease];
    p.desc = @"点击唤醒之后,创建的对象";
    NSLog(@"---- touch 事件 结束了");
}

/**
 ------->唤醒之后
 处理timers之前
 处理source之前

 ---- touch 事件 开始了 
 ---- touch 事件 结束了
 Person:点击唤醒之后,创建的对象 dealloc

 处理timers之前
*/
```
可以看到处理完点击事件之后(Source0),`autorelease`对象就释放了,也没有等到`runloop`处于休眠状态.用上面同样的方法查看一下方法调用栈
![avatar](https://s1.ax1x.com/2020/04/26/JRmO6s.md.png)

综合上面的分析,我们知道系统在主线程runloop是有默认创建自动释放池的,且它的释放时机并不局限于`kCFRunLoopBeforeWaiting`状态,在处理完`Timer`和`Source`事件之后,都会插入释放操作.

### main函数中@autoreleasepool作用
```
int main(int argc, char * argv[]) {
    NSString * appDelegateClassName;
    @autoreleasepool {
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
        return UIApplicationMain(argc, argv, nil, appDelegateClassName);
    }
}
```
`UIApplicationMain`中是一个`do-while`循环,只要程序不退出`return`之后的代码永远不执行.所以`main`函数中的`@autoreleasepool`可以看做是当程序退出时,释放自动释放池中未释放的对象,是一个清理内存的操作.

### 子线程中autoreleasepool
子线程默认并没有runloop,那么向子线程中的对象添加`autorelease`描述会发生什么?`autorelease`对象又是什么时候释放的呢?
```
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

/**
打印分析:
 start
 end
 block start
 block end
Person:子线程创建的autorelease对象 dealloc
*/
```
可以看到子线程中`autorelease`对象,在线程任务执行完会自动销毁.
针对子线程中用`autorelease`描述对象,其实与主线程并无不同,在上面已经分析过.在没有自动释放池的时候,会自动创建,方法调用顺序为`autorelease -> autoreleaseFast -> autoreleaseNoPage。`

那么怎么销毁呢?
按照刚刚的方法,通过在dealloc打断点和`thread backtrace`分析
![avatar](https://s1.ax1x.com/2020/04/27/JRMv2F.png)
发现其在释放之前调用了`tls_dealloc`方法,到runtime中查看一下其源码
```
static void tls_dealloc(void *p) 
{
    if (p == (void*)EMPTY_POOL_PLACEHOLDER) {
        // No objects or pool pages to clean up here.
        return;
    }

    // reinstate TLS value while we work
    setHotPage((AutoreleasePoolPage *)p);

    if (AutoreleasePoolPage *page = coldPage()) {
        if (!page->empty()) pop(page->begin());  // pop all of the pools
        if (DebugMissingPools || DebugPoolAllocation) {
            // pop() killed the pages already
        } else {
            page->kill();  // free all of the pages
        }
    }
    
    // clear TLS value so TLS destruction doesn't loop
    setHotPage(nil);
}
```
在`tls_dealloc`中执行`page->kill()`释放掉所有page.

通过以上分析可知:

* 子线程中用`autorelease`描述对象,会默认创建自动释放池

* 子线程中的自动释放池,在线程销毁的时候会统一释放



