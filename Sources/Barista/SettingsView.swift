import SwiftUI

struct SettingsView: View {
  @ObservedObject var controller: AppDelegate
  @State private var showingHelp = false

  var body: some View {
    VStack(spacing: 0) {
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 20) {
          HStack(spacing: 14) {
            Image(nsImage: StatusIconStyle.coffeeBean.image(collapsed: true))
              .resizable().frame(width: 36, height: 36).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
              Text("Barista").font(.system(size: 25, weight: .bold))
              Text("필요한 아이콘만 남기고, 나머지는 접어 두세요.")
                .foregroundStyle(.secondary)
            }
          }

          if controller.accessibilityGranted {
            Label("손쉬운 사용 권한 완료", systemImage: "checkmark.circle.fill")
              .font(.callout.weight(.medium))
              .foregroundStyle(.green)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(12)
              .background(Color.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
          } else {
            VStack(alignment: .leading, spacing: 8) {
              Label("손쉬운 사용 권한이 필요해요", systemImage: "hand.raised")
                .fontWeight(.semibold)
              Text("메뉴 막대 아이콘의 위치를 읽는 데 사용합니다. 시스템 설정에서 이 앱을 허용해 주세요.")
                .font(.callout).foregroundStyle(.secondary)
              HStack {
                Button("손쉬운 사용 설정 열기") { controller.openAccessibilitySettings() }
                Button("권한 다시 확인") { controller.refreshEnvironment() }
              }
            }
            .padding(14)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
          }

          if let message = controller.statusMessage {
            Label(message, systemImage: "info.circle")
              .font(.callout).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          if !controller.competingManagers.isEmpty {
            Label(
              "\(controller.competingManagers.joined(separator: ", ")) 실행 중: 함께 사용하면 배치가 충돌할 수 있어요. 테스트할 때는 해당 앱을 종료해 주세요.",
              systemImage: "exclamationmark.triangle"
            )
            .font(.callout).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
          }

          VStack(alignment: .leading, spacing: 12) {
            Text("메뉴 막대 아이콘").fontWeight(.semibold)
            HStack(spacing: 8) {
              ForEach(StatusIconStyle.allCases) { style in
                Button {
                  controller.iconStyle = style
                } label: {
                  VStack(spacing: 8) {
                    Image(nsImage: style.image(collapsed: true))
                      .frame(width: 22, height: 22)
                    Text(style.title).font(.caption)
                  }
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 10)
                  .background(
                    controller.iconStyle == style
                      ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 10)
                  )
                  .overlay(
                    RoundedRectangle(cornerRadius: 10)
                      .stroke(
                        controller.iconStyle == style ? Color.accentColor : .clear,
                        lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(style.title)
                .accessibilityValue(controller.iconStyle == style ? "선택됨" : "선택 안 됨")
              }
            }
            Toggle("자동으로 접기", isOn: $controller.autoCollapse)
            Picker("접기까지 대기 시간", selection: $controller.autoCollapseDelay) {
              ForEach(AutoCollapseDelay.allCases) { delay in
                Text("\(delay.rawValue)초").tag(delay)
              }
            }
            .pickerStyle(.segmented)
            .disabled(!controller.autoCollapse)
            .accessibilityLabel("자동 접기 대기 시간")
            Toggle(
              "로그인할 때 실행",
              isOn: Binding(
                get: { controller.loginEnabled },
                set: { controller.setLoginEnabled($0) }
              ))
            if let message = controller.loginMessage {
              Text(message).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        .padding(28)
        .frame(width: 560)
      }
      Divider().padding(.horizontal, 28)
      HStack(spacing: 12) {
        Button {
          showingHelp.toggle()
        } label: {
          Image(systemName: "questionmark.circle")
            .font(.system(size: 20))
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("사용 방법")
        .accessibilityLabel("Barista 사용 방법")
        .popover(isPresented: $showingHelp, arrowEdge: .bottom) {
          helpContent
        }
        if controller.isApplying {
          ProgressView().controlSize(.small)
          Button("취소 · 모두 표시") { controller.setCollapsed(false) }
        } else {
          Button(controller.collapsed ? "펼치기" : "접기") { controller.toggle() }
        }
        Spacer()
        Button("완료") { controller.finishSetup() }
          .buttonStyle(.borderedProminent)
          .disabled(controller.isApplying)
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 16)
    }
    .frame(width: 560, height: 560)
    .onAppear { controller.refreshEnvironment() }
    .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
      controller.refreshAccessibilityPermission()
    }
  }

  private var helpContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Barista 사용 방법").font(.headline)
        Spacer()
        Button {
          showingHelp = false
        } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("도움말 닫기")
      }
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 10) {
          Label("숨길 아이콘", systemImage: "ellipsis.circle")
            .foregroundStyle(.secondary)
          Image(nsImage: controller.iconStyle.image(collapsed: true))
            .frame(width: 22, height: 22)
          Label("항상 표시", systemImage: "star")
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        instruction("1", "아이콘 순서 변경", "⌘ 키를 누른 채 메뉴 막대의 아이콘을 드래그하세요.")
        instruction(
          "2", "아이콘 하나로 영역 나누기", "숨길 앱은 우리 아이콘 왼쪽에, 항상 보일 앱은 오른쪽에 두세요. 커피콩도 ⌘ 키를 누른 채 드래그할 수 있어요.")
        instruction(
          "3", "클릭 또는 우클릭", "클릭하면 접기·펼치기, 우클릭하면 설정과 아이콘 선택 메뉴가 열려요. Control + 클릭으로도 메뉴를 열 수 있어요.")
      }

      Text(
        "macOS 27에서는 앱 단위로 숨기므로 한 앱의 아이콘은 함께 접힙니다. Wi‑Fi·배터리 등 시스템 아이콘도 왼쪽에 두면 접힙니다. 같은 앱이나 시스템 프로세스가 만든 여러 아이콘은 함께 처리될 수 있습니다. 시계·제어 센터 위에서는 시스템 메뉴를 사용할 수 있도록 잠시 펼쳐져요."
      )
      .font(.callout).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(20)
    .frame(width: 390)
  }

  private func instruction(_ number: String, _ title: String, _ detail: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(number).font(.caption.bold())
        .frame(width: 24, height: 24)
        .background(.tint.opacity(0.12), in: Circle())
      VStack(alignment: .leading, spacing: 3) {
        Text(title).fontWeight(.semibold)
        Text(detail).font(.callout).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}
