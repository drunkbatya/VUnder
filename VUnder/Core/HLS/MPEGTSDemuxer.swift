import Foundation

struct MPEGTSDemuxer {
    private static let packetSize = 188
    private static let syncByte: UInt8 = 0x47
    private static let audioStreamTypes: Set<UInt8> = [0x03, 0x04, 0x0F]

    private var programMapPID: Int?
    private var audioPID: Int?
    private(set) var audioStreamType: UInt8?
    private var pendingPacket = Data()

    mutating func demux(_ segment: Data) throws -> Data {
        var input = pendingPacket + segment
        pendingPacket = Data()
        var output = Data()
        var offset = 0
        while offset + MPEGTSDemuxer.packetSize <= input.count {
            guard input[offset] == MPEGTSDemuxer.syncByte else {
                offset += 1
                continue
            }
            let packet = input.subdata(in: offset..<(offset + MPEGTSDemuxer.packetSize))
            try handle(packet: packet, output: &output)
            offset += MPEGTSDemuxer.packetSize
        }
        if offset < input.count {
            pendingPacket = input.subdata(in: offset..<input.count)
        }
        input.removeAll()
        return output
    }

    private mutating func handle(packet: Data, output: inout Data) throws {
        let payloadUnitStart = packet[1] & 0x40 != 0
        let pid = Int(packet[1] & 0x1F) << 8 | Int(packet[2])
        let adaptationControl = (packet[3] >> 4) & 0x03
        var payloadOffset = 4
        if adaptationControl == 0x02 {
            return
        }
        if adaptationControl == 0x03 {
            payloadOffset += 1 + Int(packet[4])
        }
        guard payloadOffset < packet.count else { return }
        let payload = packet.subdata(in: payloadOffset..<packet.count)

        if pid == 0 {
            if payloadUnitStart, let table = MPEGTSDemuxer.section(payload) {
                programMapPID = MPEGTSDemuxer.parseProgramAssociation(table)
            }
            return
        }
        if pid == programMapPID {
            if payloadUnitStart, let table = MPEGTSDemuxer.section(payload) {
                let audio = MPEGTSDemuxer.parseProgramMap(table)
                audioPID = audio?.pid
                audioStreamType = audio?.streamType
            }
            return
        }
        guard pid == audioPID else { return }
        if payloadUnitStart {
            guard payload.count >= 9, payload[0] == 0, payload[1] == 0, payload[2] == 1 else { return }
            let headerLength = Int(payload[8])
            let start = 9 + headerLength
            guard start <= payload.count else { return }
            output.append(payload.subdata(in: start..<payload.count))
        } else {
            output.append(payload)
        }
    }

    private static func section(_ payload: Data) -> Data? {
        guard let pointer = payload.first else { return nil }
        let start = 1 + Int(pointer)
        guard start + 3 <= payload.count else { return nil }
        let sectionLength = Int(payload[start + 1] & 0x0F) << 8 | Int(payload[start + 2])
        let end = min(start + 3 + sectionLength, payload.count)
        return payload.subdata(in: start..<end)
    }

    private static func parseProgramAssociation(_ table: Data) -> Int? {
        guard table[0] == 0x00, table.count > 12 else { return nil }
        var offset = 8
        while offset + 4 <= table.count - 4 {
            let programNumber = Int(table[offset]) << 8 | Int(table[offset + 1])
            let pid = Int(table[offset + 2] & 0x1F) << 8 | Int(table[offset + 3])
            if programNumber != 0 {
                return pid
            }
            offset += 4
        }
        return nil
    }

    private static func parseProgramMap(_ table: Data) -> (pid: Int, streamType: UInt8)? {
        guard table[0] == 0x02, table.count > 16 else { return nil }
        let programInfoLength = Int(table[10] & 0x0F) << 8 | Int(table[11])
        var offset = 12 + programInfoLength
        while offset + 5 <= table.count - 4 {
            let streamType = table[offset]
            let pid = Int(table[offset + 1] & 0x1F) << 8 | Int(table[offset + 2])
            let infoLength = Int(table[offset + 3] & 0x0F) << 8 | Int(table[offset + 4])
            if audioStreamTypes.contains(streamType) {
                return (pid, streamType)
            }
            offset += 5 + infoLength
        }
        return nil
    }
}
