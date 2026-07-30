import CryptoKit
import Foundation

let privateKey = Curve25519.Signing.PrivateKey()

print("SPARKLE_PUBLIC_ED_KEY=\(privateKey.publicKey.rawRepresentation.base64EncodedString())")
print("SPARKLE_ED_PRIVATE_KEY=\(privateKey.rawRepresentation.base64EncodedString())")
