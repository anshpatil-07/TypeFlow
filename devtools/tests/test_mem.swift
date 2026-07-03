import Foundation
import Darwin

let hostPort = mach_host_self()
var pageSize: vm_size_t = 0
host_page_size(hostPort, &pageSize)

var vmStats = vm_statistics64()
var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

let statsResult = withUnsafeMutablePointer(to: &vmStats) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
    }
}

let availablePages = UInt64(vmStats.free_count) + UInt64(vmStats.inactive_count) + UInt64(vmStats.speculative_count)
let availableBytes = availablePages * UInt64(pageSize)

print("Available memory: \(availableBytes / 1024 / 1024) MB")
