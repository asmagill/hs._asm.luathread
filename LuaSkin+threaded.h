extern NSMapTable *threadToSkinMap ;
extern NSMapTable *threadToRefTableMap ;

@interface LuaSkin (threaded)
+ (id)threaded ;
- (int)refTableFor:(const char *)tagName ;
@end

