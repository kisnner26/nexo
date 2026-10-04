import NexoCore
import SwiftUI

struct PairingView: View {
    @ObservedObject var model: PhoneModel
    @State private var text = ""
    @State private var failed = false

    var body: some View {
        ZStack {
            NXBackdrop()
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "macbook.and.iphone").font(.system(size: 54, weight: .light))
                    .frame(width: 112, height: 112).glassEffect(.regular, in: .circle)
                VStack(spacing: 8) {
                    Text("Conecta tu Mac").font(.largeTitle.bold())
                    Text("Abre Nexo en la Mac, haz clic en su icono de la barra de menús y escribe el código. El Apple Watch lo recibe solo.")
                        .font(.subheadline).foregroundStyle(NX.mute).multilineTextAlignment(.center)
                }
                TextField("XXXX-XXXX-XXXX", text: $text)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(.system(size: 22, weight: .medium, design: .monospaced)).multilineTextAlignment(.center)
                    .padding(.vertical, 16).padding(.horizontal, 20)
                    .glassEffect(.regular, in: .capsule)
                if failed { Text("El código no es válido").font(.footnote).foregroundStyle(NX.red) }
                Button { failed = !model.pair(text) } label: {
                    Text("Emparejar").font(.headline).frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.glassProminent).buttonBorderShape(.capsule).tint(NX.blue).controlSize(.large)
                .disabled(text.isEmpty)
                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .preferredColorScheme(.dark)
    }
}
