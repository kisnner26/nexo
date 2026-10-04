import Darwin
import Foundation

enum SystemStats {
    private static var previous: host_cpu_load_info?

    static func cpuPercent() -> Int {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard r == KERN_SUCCESS else { return 0 }
        defer { previous = info }
        guard let p = previous else { return 0 }
        let user = Double(info.cpu_ticks.0 &- p.cpu_ticks.0)
        let sys = Double(info.cpu_ticks.1 &- p.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- p.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- p.cpu_ticks.3)
        let total = user + sys + idle + nice
        return total > 0 ? Int((user + sys + nice) / total * 100) : 0
    }

    static func memoryPercent() -> Int {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64()
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard r == KERN_SUCCESS else { return 0 }
        let used = Double(stats.active_count + stats.wire_count + stats.compressor_page_count)
        let total = Double(ProcessInfo.processInfo.physicalMemory) / Double(vm_kernel_page_size)
        return min(100, Int(used / total * 100))
    }
}
