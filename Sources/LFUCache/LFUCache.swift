//
//  LFUCache.swift
//
//
//  Created by 黄磊 on 2020-03-17.
//

import Foundation
import NIO
import _NIOConcurrency

public final class LFUCache {
    
    /// count 记录，最多不会超过 countLimit * countRate^countRecordLevel  + countLimit * countRate^(countRecordLevel-1)  + ... + countLimit * countRate
    static var countRate = 10
    
    /// 线程
    var loop : EventLoop
    
    /// 最大缓存限制
    var countLimit : Int
    
    /// 最大保存时间
    var duration : TimeInterval
    
    /// 保存内容
    var dicContent = [String:ContentNode]()
    
    /// 保存链表
    var arrContent = NodeList()
    
    /// 规定时间内Key使用频率
    var dicCount = [String:Int]()
    
    /// 使用多级缓冲，确保不会占用太多内存
    var countRecordLevel : Int = 3
    var arrCountRecord : [CountRecord]
    /// 一级最近记录
    var lastCountRecord : CountRecord
    
    public init(loop: EventLoop, countLimit: Int, duration: TimeInterval, countRecordLevel : Int = 3) {
        
        defer {
            for index in 0..<(self.arrCountRecord.count-1) {
                let aCountRecord = self.arrCountRecord[index]
                let nextCountRecord = self.arrCountRecord[index+1]
                aCountRecord.addFullDumpBlock { (arr) in
                    for item in arr {
                        nextCountRecord.addRecord(item)
                    }
                }
            }
            let oldCountRecord = self.arrCountRecord.last!
            oldCountRecord.addFullSpillBlock {  arr in
                for item in arr {
                    self.reduceCount(key: item.1, count: item.2)
                }
            }
        }
        
        self.loop = loop
        self.countLimit = countLimit
        self.duration = duration
        self.countRecordLevel = countRecordLevel >= 1 ? countRecordLevel : 3
        self.arrCountRecord = [CountRecord]()
        
        let theRate = Self.countRate
        var aRate = 1
        for _ in 1...self.countRecordLevel {
            let prevRate = aRate
            aRate *= theRate
            let aCountRecord = CountRecord(limit: countLimit * aRate, duration: duration / Double(prevRate))
            self.arrCountRecord.insert(aCountRecord, at: 0)
        }
        self.lastCountRecord = self.arrCountRecord.first!
        
    }
    
    // MARK: - Set
    
    public func set(key: String, to value:Any) {
        setex(key: key, to: value, in: 0)
    }
    
    public func setex(key: String, to value:Any, in timeout: Int) {
        
        loop.execute {
        
            defer {
                // 这里加 count，主要是为了方便过期
                self.addCount(key: key, count: 0)
            }
            
            var expiredTime : Date? = nil
            if timeout > 0 {
                expiredTime = Date().addingTimeInterval(TimeInterval(timeout))
            }
            
            // set 不增加count
            if let node = self.dicContent[key] {
                node.content = value
                node.expiredTime = expiredTime
                return
            }
            // 新建node
            let newNode = ContentNode(key:key, content: value, count: self.dicCount[key])
            newNode.expiredTime = expiredTime
            self.arrContent.append(node: newNode)
            self.dicContent[key] = newNode
            
            // 判断是否 count 溢出
            if self.dicContent.count > self.countLimit,
                let aNode = self.arrContent.popLast() {
                self.dicContent.removeValue(forKey: aNode.key)
            }
        }
    }
    
    // MARK: - Get
    
    public func get<T>(key: String, as type: T.Type = T.self) -> EventLoopFuture<T?> {
        
        return loop.submit { () -> T? in
            defer {
                // 添加计数
                self.addCount(key: key, count: 1)
            }
            
            if let node = self.dicContent[key] {
                let expiredTime = node.expiredTime
                if expiredTime == nil || expiredTime! > Date() {
                    return node.content as? T
                } else {
                    // 删除节点
                    self.delete(key: key)
                }
            }
            
            return nil
        }
    }
    
    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    public func get<T>(key: String, as type: T.Type = T.self) async -> T? {
        
        let future = loop.submit { () -> T? in
            defer {
                // 添加计数
                self.addCount(key: key, count: 1)
            }
            
            if let node = self.dicContent[key] {
                let expiredTime = node.expiredTime
                if expiredTime == nil || expiredTime! > Date() {
                    return node.content as? T
                } else {
                    // 删除节点
                    self.delete(key: key)
                }
            }
            
            return nil
        }
        
        return try? await future.get();
    }
    
    
    public func delete(key: String) {
        
        loop.execute {
            guard let node = self.dicContent[key] else {
                return
            }
            
            // 最后一个
            if node.next == nil {
                self.arrContent.lastNode = node.prev
            }
            
            self.dicContent.removeValue(forKey: node.key)
            node.prev?.next = node.next
            node.next?.prev = node.prev
            node.prev = nil
            node.next = nil
        }
    }
    
    // MARK: - Count
    
    /// 对应 key 添加计数，只在 get 时调用，即外部触发
    func addCount(key: String, count: Int) {
        // 添加记录
        let curDate = Date()
        lastCountRecord.addRecord((curDate, key, count))
        arrCountRecord.last?.checkExpired()
        // 处理累计量
        let newCount = (dicCount[key] ?? 0) + count
        dicCount[key] = newCount
        guard count > 0 else {
            return
        }
        // 处理内容
        if let node = dicContent[key] {
            node.count = newCount
            // 前移
            var newNext = node
            var didMove = false
            while let prevNode = newNext.prev, prevNode.count <= node.count {
                // 交换
                newNext = prevNode
                didMove = true
            }
            if didMove {
                // 判断 lastNode
                if node.next == nil {
                    arrContent.lastNode = node.prev
                    arrContent.lastNode?.next = nil
                }
                // 隔断当前
                node.next?.prev = node.prev
                node.prev?.next = node.next
                // 接上新位置
                newNext.prev?.next = node
                node.prev = newNext.prev
                newNext.prev = node
                node.next = newNext
            }
        }
    }
    
    /// 对应 key 减少计数，只会是内部 CountRecord 通知
    func reduceCount(key: String, count: Int) {
        if let aCount = self.dicCount[key] {
            let newCount = aCount - count
            if newCount <= 0 {
                self.dicCount.removeValue(forKey: key)
                if let node = self.dicContent[key] {
                    node.prev?.next = node.next
                    node.next?.prev = node.prev
                    // 判断删除的这个是不是 last
                    if node.next == nil {
                        arrContent.lastNode = node.prev
                        arrContent.lastNode?.next = nil
                    }
                    node.prev = nil
                    node.next = nil
                    print("Auto delete \(key)")
                    self.dicContent.removeValue(forKey: key)
                }
            } else {
                self.dicCount[key] = newCount
                if let node = dicContent[key] {
                    // 后移
                    node.count = newCount
                    var newPrev = node
                    var didMove = false
                    while let nextNode = newPrev.next, nextNode.count >= node.count {
                        // 交换
                        newPrev = nextNode
                        didMove = true
                    }
                    if didMove {
                        // 隔断当前
                        node.prev?.next = node.next
                        node.next?.prev = node.prev
                        // 接上新位置
                        newPrev.next?.prev = node
                        node.next = newPrev.next
                        newPrev.next = node
                        node.prev = newPrev
                        // 判断 lastNode
                        if node.next == nil {
                            arrContent.lastNode = node
                        }
                    }
                }
            }
        }
    }
    
    
    // MARK: - ContentNode
    
    /// 内容节点，用于保存内容的节点
    final class ContentNode {
        
        var key : String
        var content : Any
        var count : Int = 0
        
        var prev : ContentNode? = nil
        var next : ContentNode? = nil
        
        var expiredTime : Date?
        
        init(key: String, content: Any, count: Int? = 0) {
            self.key = key
            self.content = content
            self.count = count ?? 0
        }
    }
    
    final class NodeList {
        var lastNode : ContentNode?
        
        func append(node : ContentNode) {
            
            var aOptionNode = lastNode
            var didMove = false
            while let aNode = aOptionNode {
                if aNode.count <= node.count {
                    // 前移
                    didMove = true
                    if let aaNode = aNode.prev {
                        aOptionNode = aaNode
                    } else {
                        break
                    }
                } else {
                    break
                }
            }
            if didMove {
                aOptionNode?.prev?.next = node
                node.prev = aOptionNode?.prev
                node.next = aOptionNode
                aOptionNode?.prev = node
            } else {
                node.prev = lastNode
                lastNode?.next = node
                lastNode = node
                lastNode?.next = nil
            }
        }
        
        func popLast() -> ContentNode? {
            if let aNode = lastNode {
                lastNode = lastNode?.prev
                // 这里需要清理一下
                lastNode?.next = nil
                aNode.prev = nil
                aNode.next = nil
                return aNode
            }
            return nil
        }
    }
    
    
    // MARK: - CountRecord
    
    /// 次数记录，用于记录一段时间内的访问记录
    final class CountRecord : CustomStringConvertible {
        let limit : Int
        let duration : TimeInterval
        var arrRecord = [(Date, String, Int)]()
        var createDate : Date
        var fullDumpBlock : (([(Date, String, Int)]) -> Void)?
        var fullSpillBlock : (([(Date, String, Int)]) -> Void)?
        
        init(limit: Int, duration: TimeInterval) {
            self.limit = limit
            self.duration = duration
            self.createDate = Date()
        }
        
        func addFullDumpBlock(_ block : @escaping ([(Date, String, Int)]) -> Void) {
            fullDumpBlock = block
        }
        
        func addFullSpillBlock(_ block : @escaping ([(Date, String, Int)]) -> Void) {
            fullSpillBlock = block
        }
        
        func addRecord(_ item: (Date, String, Int)) {
            
            arrRecord.insert(item, at: 0)
            let curDate = Date()
            if arrRecord.count == 1 {
                createDate = curDate
            }
            
            // 判断是否满了，或者有可能当前传进来的已经过期了
            if arrRecord.count > limit ||
                curDate > createDate.addingTimeInterval(duration) ||
                curDate > item.0.addingTimeInterval(duration) {
                // 开始处理
                if let aFullDumpBlock = fullDumpBlock {
                    // 全部倾倒
                    var dicRecord = [String:(Date, String, Int)]()
                    var arrKeys = [String]()
                    for aRecord in arrRecord {
                        let key = aRecord.1
                        if var aSum = dicRecord[key] {
                            // 已存在
                            aSum.2 += aRecord.2
                            dicRecord[key] = aSum
                        } else {
                            arrKeys.append(key)
                            dicRecord[key] = aRecord
                        }
                    }
                    var arrResult = [(Date, String, Int)]()
                    for aKey in arrKeys {
                        arrResult.append(dicRecord[aKey]!)
                    }
                    aFullDumpBlock(arrResult)
                    arrRecord.removeAll()
                } else {
                    checkExpired()
                }
            }
        }
        
        /// 检查并踢出过期的
        func checkExpired() {
            guard let aFullSpillBlock = fullSpillBlock else {
                return
            }
            let curDate = Date()
            // 处理溢出
            var dicRecord = [String:(Date, String, Int)]()
            var arrKeys = [String]()
            var index = 0
            // 超时和超个数溢出
            var spillCount = arrRecord.count - limit
            if spillCount > 0 && arrRecord.last!.0.addingTimeInterval(duration) >= curDate {
                // 超出但未过期
                print("Count limit reached. You need turn up countLimit or turn down duration")
            }
            for aRecord in arrRecord.reversed() {
                if curDate > aRecord.0.addingTimeInterval(duration) || spillCount > 0 {
                    let key = aRecord.1
                    if var aSum = dicRecord[key] {
                        // 已存在
                        aSum.2 += aRecord.2
                        dicRecord[key] = aSum
                    } else {
                        arrKeys.insert(key, at: 0)
                        dicRecord[key] = aRecord
                    }
                    index += 1
                    spillCount -= 1
                }
                break
            }
            
            var arrResult = [(Date, String, Int)]()
            for aKey in arrKeys {
                arrResult.append(dicRecord[aKey]!)
            }
            aFullSpillBlock(arrResult)
            arrRecord.removeLast(index)
        }
        
        public var description : String {
            var str = "\n"
            for item in arrRecord {
                str += "\(item.0)   \(item.1)   \(item.2)\n"
            }
            return str
        }
        
    }
    
    
    
}
