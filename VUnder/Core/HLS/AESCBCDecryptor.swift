import CommonCrypto
import Foundation

enum AESCBCDecryptor {
    static func decrypt(_ data: Data, key: Data, iv: Data) throws -> Data {
        var output = Data(count: data.count + kCCBlockSizeAES128)
        var produced = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress, data.count,
                            outputBytes.baseAddress, outputBytes.count,
                            &produced
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw HLSError.decryptFailed(status)
        }
        output.count = produced
        return output
    }
}
