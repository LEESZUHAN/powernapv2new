import SwiftUI

// 導入PowerNapViewModel
@preconcurrency import Foundation

/// 睡眠確認時間按鈕
struct SleepConfirmationTimeButton: View {
    @ObservedObject var viewModel: PowerNapViewModel
    
    var body: some View {
        HStack {
            // 左側圖標和文字
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .foregroundColor(.blue)
                        .font(.system(size: 16))
                    
                    Text("睡眠確認時間")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                
                Text("設定判定睡眠所需的時間")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // 右側只顯示導航箭頭，不顯示時間
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.gray)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.2, opacity: 0.7))
        )
        .contentShape(Rectangle()) // 確保整個區域可點擊
        .buttonStyle(PlainButtonStyle()) // 使用普通按鈕樣式，避免導航鏈接樣式干擾
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
} 