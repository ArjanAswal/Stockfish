#import "StockfishPlugin.h"
#if __has_include(<stockfish/stockfish-Swift.h>)
#import <stockfish/stockfish-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "stockfish-Swift.h"
#endif

@implementation StockfishPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftStockfishPlugin registerWithRegistrar:registrar];
}
@end
