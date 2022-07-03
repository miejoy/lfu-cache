# LFUCache

LFUCache 是一个适用于服务器使用的缓存模块。会缓存最近一段时间内最频繁使用的内容。

[![Swift](https://github.com/miejoy/lfu-cache/actions/workflows/test.yml/badge.svg)](https://github.com/miejoy/lfu-cache/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/miejoy/lfu-cache/branch/main/graph/badge.svg)](https://codecov.io/gh/miejoy/lfu-cache)
[![License](https://img.shields.io/badge/license-MIT-brightgreen.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/swift-5.2-brightgreen.svg)](https://swift.org)

## 依赖

- iOS 13.0+ / macOS 10.15+
- Xcode 12.0+
- Swift 5.2+

## 简介

LFUCacahe (Latest Frequently Used Cache) 使用按时间分层的方式缓存了每个 key 的使用次数，每当当前层记录满了或时间到了，会将所有记录总结后传到下一次，最后一层满了会倾倒所有缓存记录。
这里在创建缓存时需要如下参数：
- loop: EventLoop, 缓存操作所在的 event loop
- countLimit: Int, 最大缓存个数
- duration: TimeInterval, 最大记录缓存时间，超过这段时间的记录将被移除，也只有在这段时间的记录才会统计使用次数
- countRecordLevel : Int, 记录分层数，默认分 3 层，每次记录时间范围递增10倍，比如第一层记录 10 分钟，第二次记录 100 分钟 等的，所以记录都从第一层开始，满了之后传到下一层

## 安装

### [Swift Package Manager](https://github.com/apple/swift-package-manager)

在项目中的 Package.swift 文件添加如下依赖:

```swift
dependencies: [
    .package(url: "https://github.com/miejoy/lfu-cache.git", from: "0.1.0"),
]
```

## 使用

### LFUCache 使用

1、初始化

```swift
import LFUCache

let cache = LFUCache(loop: app.eventLoopGroup.next(), countLimit: 1000, duration: 12 * 3600)
```

2、使用

```swift
import LFUCache

// 添加缓存
cache.set(key: key, to: value)

// 添加自动超时的缓存，超时时间要小于 cache 的 duration
cache.setex(key: key, to: value, in: timeout)

// 读取缓存
let value = try await cache.get(key: key, as: Value.self)

// 删除缓存
cache.delete(key: key)
```

## 作者

Raymond.huang: raymond0huang@gmail.com

## License

LFUCache is available under the MIT license. See the LICENSE file for more info.
