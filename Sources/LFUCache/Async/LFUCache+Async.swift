//
//  LFUCache+Async.swift
//  
//
//  Created by 黄磊 on 2022/3/20.
//

import Foundation
import NIO

extension LFUCache {

    // MARK: - Set

//    public func set(key: String, to value:Any) {
//        setex(key: key, to: value, in: 0)
//    }

    public func setex(key: String, to value:Any, in timeout: Int) async throws {
        try await loop.submit {
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
        }.get()
    }

    // MARK: - Get

    public func get<T>(key: String, as type: T.Type = T.self) async throws -> T? {
        return try await loop.submit { () -> T? in
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
        }.get()
    }

//    public func delete(key: String) {
//
//        loop.execute {
//            guard let node = self.dicContent[key] else {
//                return
//            }
//
//            // 最后一个
//            if node.next == nil {
//                self.arrContent.lastNode = node.prev
//            }
//
//            self.dicContent.removeValue(forKey: node.key)
//            node.prev?.next = node.next
//            node.next?.prev = node.prev
//            node.prev = nil
//            node.next = nil
//        }
//    }
}
