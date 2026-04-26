import SwiftUI

// ============================================================
// Android NuruIcons.kt の全アイコンを SwiftUI Canvas で忠実に再現。
// Viewport: 全て 24×24。foreground カラーで描画し、呼び出し側で
// .foregroundStyle() を設定して色を変更する。
// ============================================================

// MARK: - Helper

/// 24×24 viewport → Canvas size への座標変換ヘルパー
private func pt(_ x: CGFloat, _ y: CGFloat, _ sx: CGFloat, _ sy: CGFloat) -> CGPoint {
    CGPoint(x: x * sx, y: y * sy)
}

// MARK: - Close (×)

struct CloseIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.move(to: pt(18, 6, sx, sy)); p.addLine(to: pt(6, 18, sx, sy))
            p.move(to: pt(6, 6, sx, sy)); p.addLine(to: pt(18, 18, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Video

struct VideoIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            // Play triangle
            p.move(to: pt(23, 7, sx, sy)); p.addLine(to: pt(16, 12, sx, sy)); p.addLine(to: pt(23, 17, sx, sy)); p.closeSubpath()
            // Camera body
            p.move(to: pt(3, 5, sx, sy)); p.addLine(to: pt(14, 5, sx, sy))
            p.addQuadCurve(to: pt(16, 7, sx, sy), control: pt(16, 5, sx, sy))
            p.addLine(to: pt(16, 17, sx, sy))
            p.addQuadCurve(to: pt(14, 19, sx, sy), control: pt(16, 19, sx, sy))
            p.addLine(to: pt(3, 19, sx, sy))
            p.addQuadCurve(to: pt(1, 17, sx, sy), control: pt(1, 19, sx, sy))
            p.addLine(to: pt(1, 7, sx, sy))
            p.addQuadCurve(to: pt(3, 5, sx, sy), control: pt(1, 5, sx, sy))
            p.closeSubpath()
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Photo (Image)

struct PhotoIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            // Rectangle
            p.move(to: pt(5, 3, sx, sy)); p.addLine(to: pt(19, 3, sx, sy))
            p.addQuadCurve(to: pt(21, 5, sx, sy), control: pt(21, 3, sx, sy))
            p.addLine(to: pt(21, 19, sx, sy))
            p.addQuadCurve(to: pt(19, 21, sx, sy), control: pt(21, 21, sx, sy))
            p.addLine(to: pt(5, 21, sx, sy))
            p.addQuadCurve(to: pt(3, 19, sx, sy), control: pt(3, 21, sx, sy))
            p.addLine(to: pt(3, 5, sx, sy))
            p.addQuadCurve(to: pt(5, 3, sx, sy), control: pt(3, 3, sx, sy))
            p.closeSubpath()
            // Sun
            p.addEllipse(in: CGRect(x: 7 * sx, y: 7 * sy, width: 3 * sx, height: 3 * sy))
            // Mountain
            p.move(to: pt(21, 15, sx, sy)); p.addLine(to: pt(16, 10, sx, sy)); p.addLine(to: pt(5, 21, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Warning (△!)

struct WarningIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.move(to: pt(10.29, 3.86, sx, sy))
            p.addLine(to: pt(1.82, 18, sx, sy))
            p.addQuadCurve(to: pt(3.53, 21, sx, sy), control: pt(0.82, 20, sx, sy))
            p.addLine(to: pt(20.47, 21, sx, sy))
            p.addQuadCurve(to: pt(22.18, 18, sx, sy), control: pt(22.18, 20, sx, sy))
            p.addLine(to: pt(13.71, 3.86, sx, sy))
            p.addQuadCurve(to: pt(10.29, 3.86, sx, sy), control: pt(12, 1.86, sx, sy))
            p.closeSubpath()
            p.move(to: pt(12, 9, sx, sy)); p.addLine(to: pt(12, 13, sx, sy))
            p.move(to: pt(12, 17, sx, sy)); p.addLine(to: pt(12.01, 17, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Emoji (smiley)

struct EmojiIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.addEllipse(in: CGRect(x: 2 * sx, y: 2 * sy, width: 20 * sx, height: 20 * sy))
            // Smile
            p.move(to: pt(8, 14, sx, sy))
            p.addCurve(to: pt(16, 14, sx, sy), control1: pt(9.5, 16, sx, sy), control2: pt(14.5, 16, sx, sy))
            // Eyes
            p.move(to: pt(9, 9, sx, sy)); p.addLine(to: pt(9.01, 9, sx, sy))
            p.move(to: pt(15, 9, sx, sy)); p.addLine(to: pt(15.01, 9, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Mic

struct MicIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            // Mic body
            p.move(to: pt(12, 1, sx, sy))
            p.addQuadCurve(to: pt(9, 4, sx, sy), control: pt(9, 1, sx, sy))
            p.addLine(to: pt(9, 12, sx, sy))
            p.addQuadCurve(to: pt(12, 15, sx, sy), control: pt(9, 15, sx, sy))
            p.addQuadCurve(to: pt(15, 12, sx, sy), control: pt(15, 15, sx, sy))
            p.addLine(to: pt(15, 4, sx, sy))
            p.addQuadCurve(to: pt(12, 1, sx, sy), control: pt(15, 1, sx, sy))
            p.closeSubpath()
            // Pickup
            p.move(to: pt(19, 10, sx, sy)); p.addLine(to: pt(19, 12, sx, sy))
            p.addQuadCurve(to: pt(12, 19, sx, sy), control: pt(19, 19, sx, sy))
            p.addQuadCurve(to: pt(5, 12, sx, sy), control: pt(5, 19, sx, sy))
            p.addLine(to: pt(5, 10, sx, sy))
            // Stand
            p.move(to: pt(12, 19, sx, sy)); p.addLine(to: pt(12, 23, sx, sy))
            p.move(to: pt(8, 23, sx, sy)); p.addLine(to: pt(16, 23, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Website (globe)

struct WebsiteIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.addEllipse(in: CGRect(x: 2 * sx, y: 2 * sy, width: 20 * sx, height: 20 * sy))
            p.move(to: pt(2, 12, sx, sy)); p.addLine(to: pt(22, 12, sx, sy))
            // Vertical arcs (meridians)
            p.move(to: pt(12, 2, sx, sy))
            p.addQuadCurve(to: pt(12, 22, sx, sy), control: pt(20, 12, sx, sy))
            p.move(to: pt(12, 2, sx, sy))
            p.addQuadCurve(to: pt(12, 22, sx, sy), control: pt(4, 12, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 1.8 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Cake (birthday)

struct CakeIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            // Box
            p.move(to: pt(20, 21, sx, sy)); p.addLine(to: pt(20, 13, sx, sy))
            p.addQuadCurve(to: pt(18, 11, sx, sy), control: pt(20, 11, sx, sy))
            p.addLine(to: pt(6, 11, sx, sy))
            p.addQuadCurve(to: pt(4, 13, sx, sy), control: pt(4, 11, sx, sy))
            p.addLine(to: pt(4, 21, sx, sy))
            // Icing wave
            p.move(to: pt(4, 16, sx, sy))
            p.addCurve(to: pt(8, 17, sx, sy), control1: pt(4.5, 15, sx, sy), control2: pt(6, 15, sx, sy))
            p.addCurve(to: pt(12, 15, sx, sy), control1: pt(10.5, 19, sx, sy), control2: pt(9.5, 19, sx, sy))
            p.addCurve(to: pt(16, 17, sx, sy), control1: pt(14.5, 19, sx, sy), control2: pt(13.5, 19, sx, sy))
            p.addCurve(to: pt(20, 16, sx, sy), control1: pt(18, 15, sx, sy), control2: pt(19.5, 15, sx, sy))
            // Base
            p.move(to: pt(2, 21, sx, sy)); p.addLine(to: pt(22, 21, sx, sy))
            // Candles
            p.move(to: pt(7, 8, sx, sy)); p.addLine(to: pt(7, 10, sx, sy))
            p.move(to: pt(12, 8, sx, sy)); p.addLine(to: pt(12, 10, sx, sy))
            p.move(to: pt(17, 8, sx, sy)); p.addLine(to: pt(17, 10, sx, sy))
            // Flames
            p.move(to: pt(7, 4, sx, sy)); p.addLine(to: pt(7.01, 4, sx, sy))
            p.move(to: pt(12, 4, sx, sy)); p.addLine(to: pt(12.01, 4, sx, sy))
            p.move(to: pt(17, 4, sx, sy)); p.addLine(to: pt(17.01, 4, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Search

struct SearchIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.addEllipse(in: CGRect(x: 3 * sx, y: 3 * sy, width: 16 * sx, height: 16 * sy))
            p.move(to: pt(21, 21, sx, sy)); p.addLine(to: pt(16.65, 16.65, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Lock

struct LockIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            // Shackle
            p.move(to: pt(8, 8, sx, sy)); p.addLine(to: pt(8, 6, sx, sy))
            p.addQuadCurve(to: pt(12, 2, sx, sy), control: pt(8, 2, sx, sy))
            p.addQuadCurve(to: pt(16, 6, sx, sy), control: pt(16, 2, sx, sy))
            p.addLine(to: pt(16, 8, sx, sy))
            // Body
            p.move(to: pt(18, 8, sx, sy))
            p.addQuadCurve(to: pt(20, 10, sx, sy), control: pt(20, 8, sx, sy))
            p.addLine(to: pt(20, 20, sx, sy))
            p.addQuadCurve(to: pt(18, 22, sx, sy), control: pt(20, 22, sx, sy))
            p.addLine(to: pt(6, 22, sx, sy))
            p.addQuadCurve(to: pt(4, 20, sx, sy), control: pt(4, 22, sx, sy))
            p.addLine(to: pt(4, 10, sx, sy))
            p.addQuadCurve(to: pt(6, 8, sx, sy), control: pt(4, 8, sx, sy))
            p.addLine(to: pt(18, 8, sx, sy))
            p.closeSubpath()
            // Keyhole
            p.addEllipse(in: CGRect(x: 11 * sx, y: 14 * sy, width: 2 * sx, height: 2 * sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Badge (rosette)

struct BadgeIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.addEllipse(in: CGRect(x: 6 * sx, y: 2 * sy, width: 12 * sx, height: 12 * sy))
            p.move(to: pt(12, 14, sx, sy)); p.addLine(to: pt(12, 22, sx, sy))
            p.move(to: pt(9, 18, sx, sy)); p.addLine(to: pt(12, 21, sx, sy)); p.addLine(to: pt(15, 18, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 1.8 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Scheduler (calendar)

struct SchedulerIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.move(to: pt(5, 4, sx, sy)); p.addLine(to: pt(19, 4, sx, sy))
            p.addQuadCurve(to: pt(21, 6, sx, sy), control: pt(21, 4, sx, sy))
            p.addLine(to: pt(21, 20, sx, sy))
            p.addQuadCurve(to: pt(19, 22, sx, sy), control: pt(21, 22, sx, sy))
            p.addLine(to: pt(5, 22, sx, sy))
            p.addQuadCurve(to: pt(3, 20, sx, sy), control: pt(3, 22, sx, sy))
            p.addLine(to: pt(3, 6, sx, sy))
            p.addQuadCurve(to: pt(5, 4, sx, sy), control: pt(3, 4, sx, sy))
            p.closeSubpath()
            p.move(to: pt(16, 2, sx, sy)); p.addLine(to: pt(16, 6, sx, sy))
            p.move(to: pt(8, 2, sx, sy)); p.addLine(to: pt(8, 6, sx, sy))
            p.move(to: pt(3, 10, sx, sy)); p.addLine(to: pt(21, 10, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 1.8 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Relay (network)

struct RelayIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.addEllipse(in: CGRect(x: 9 * sx, y: 9 * sy, width: 6 * sx, height: 6 * sy))
            p.addEllipse(in: CGRect(x: 4 * sx, y: 4 * sy, width: 16 * sx, height: 16 * sy))
            p.move(to: pt(12, 2, sx, sy)); p.addLine(to: pt(12, 6, sx, sy))
            p.move(to: pt(12, 18, sx, sy)); p.addLine(to: pt(12, 22, sx, sy))
            p.move(to: pt(2, 12, sx, sy)); p.addLine(to: pt(6, 12, sx, sy))
            p.move(to: pt(18, 12, sx, sy)); p.addLine(to: pt(22, 12, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 1.8 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Backup (upload)

struct BackupIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.move(to: pt(21, 15, sx, sy)); p.addLine(to: pt(21, 19, sx, sy))
            p.addQuadCurve(to: pt(19, 21, sx, sy), control: pt(21, 21, sx, sy))
            p.addLine(to: pt(5, 21, sx, sy))
            p.addQuadCurve(to: pt(3, 19, sx, sy), control: pt(3, 21, sx, sy))
            p.addLine(to: pt(3, 15, sx, sy))
            p.move(to: pt(17, 8, sx, sy)); p.addLine(to: pt(12, 3, sx, sy)); p.addLine(to: pt(7, 8, sx, sy))
            p.move(to: pt(12, 3, sx, sy)); p.addLine(to: pt(12, 15, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 1.8 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Download

struct DownloadIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.move(to: pt(21, 15, sx, sy)); p.addLine(to: pt(21, 19, sx, sy))
            p.addQuadCurve(to: pt(19, 21, sx, sy), control: pt(21, 21, sx, sy))
            p.addLine(to: pt(5, 21, sx, sy))
            p.addQuadCurve(to: pt(3, 19, sx, sy), control: pt(3, 21, sx, sy))
            p.addLine(to: pt(3, 15, sx, sy))
            p.move(to: pt(7, 10, sx, sy)); p.addLine(to: pt(12, 15, sx, sy)); p.addLine(to: pt(17, 10, sx, sy))
            p.move(to: pt(12, 15, sx, sy)); p.addLine(to: pt(12, 3, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 1.8 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Bell (notifications)

struct BellIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.move(to: pt(18, 8, sx, sy))
            p.addQuadCurve(to: pt(12, 2, sx, sy), control: pt(18, 2, sx, sy))
            p.addQuadCurve(to: pt(6, 8, sx, sy), control: pt(6, 2, sx, sy))
            p.addCurve(to: pt(3, 17, sx, sy), control1: pt(6, 15, sx, sy), control2: pt(3, 15, sx, sy))
            p.addLine(to: pt(21, 17, sx, sy))
            p.addCurve(to: pt(18, 8, sx, sy), control1: pt(21, 15, sx, sy), control2: pt(18, 15, sx, sy))
            p.closeSubpath()
            // Clapper
            p.move(to: pt(13.73, 21, sx, sy))
            p.addQuadCurve(to: pt(10.27, 21, sx, sy), control: pt(12, 23, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Repost (arrows cycle)

struct RepostIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.move(to: pt(17, 1, sx, sy)); p.addLine(to: pt(21, 5, sx, sy)); p.addLine(to: pt(17, 9, sx, sy))
            p.move(to: pt(3, 11, sx, sy)); p.addLine(to: pt(3, 9, sx, sy))
            p.addQuadCurve(to: pt(7, 5, sx, sy), control: pt(3, 5, sx, sy))
            p.addLine(to: pt(21, 5, sx, sy))
            p.move(to: pt(7, 23, sx, sy)); p.addLine(to: pt(3, 19, sx, sy)); p.addLine(to: pt(7, 15, sx, sy))
            p.move(to: pt(21, 13, sx, sy)); p.addLine(to: pt(21, 15, sx, sy))
            p.addQuadCurve(to: pt(17, 19, sx, sy), control: pt(21, 19, sx, sy))
            p.addLine(to: pt(3, 19, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 1.8 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Star

struct StarIcon: View {
    let filled: Bool
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.move(to: pt(12, 2, sx, sy))
            p.addLine(to: pt(15.09, 8.26, sx, sy)); p.addLine(to: pt(22, 9.27, sx, sy))
            p.addLine(to: pt(17, 14.14, sx, sy)); p.addLine(to: pt(18.18, 21.02, sx, sy))
            p.addLine(to: pt(12, 17.77, sx, sy)); p.addLine(to: pt(5.82, 21.02, sx, sy))
            p.addLine(to: pt(7, 14.14, sx, sy)); p.addLine(to: pt(2, 9.27, sx, sy))
            p.addLine(to: pt(8.91, 8.26, sx, sy))
            p.closeSubpath()
            if filled {
                ctx.fill(p, with: .foreground)
            }
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Send (paperplane)

struct SendIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.move(to: pt(22, 2, sx, sy)); p.addLine(to: pt(11, 13, sx, sy))
            p.move(to: pt(22, 2, sx, sy)); p.addLine(to: pt(15, 22, sx, sy)); p.addLine(to: pt(11, 13, sx, sy))
            p.addLine(to: pt(2, 9, sx, sy)); p.closeSubpath()
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Check (✓)

struct CheckIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.move(to: pt(20, 6, sx, sy)); p.addLine(to: pt(9, 17, sx, sy)); p.addLine(to: pt(4, 12, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - MoreVert (⋮ three vertical dots)

struct MoreVertIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            let r: CGFloat = 1.5
            // Three dots
            ctx.fill(Path(ellipseIn: CGRect(x: (12 - r) * sx, y: (5 - r) * sy, width: 2 * r * sx, height: 2 * r * sy)), with: .foreground)
            ctx.fill(Path(ellipseIn: CGRect(x: (12 - r) * sx, y: (12 - r) * sy, width: 2 * r * sx, height: 2 * r * sy)), with: .foreground)
            ctx.fill(Path(ellipseIn: CGRect(x: (12 - r) * sx, y: (19 - r) * sy, width: 2 * r * sx, height: 2 * r * sy)), with: .foreground)
        }
    }
}

// MARK: - NotInterested (unhappy face)

struct NotInterestedIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.addEllipse(in: CGRect(x: 2 * sx, y: 2 * sy, width: 20 * sx, height: 20 * sy))
            p.move(to: pt(8, 15, sx, sy)); p.addLine(to: pt(16, 15, sx, sy))
            p.move(to: pt(9, 9, sx, sy)); p.addLine(to: pt(9.01, 9, sx, sy))
            p.move(to: pt(15, 9, sx, sy)); p.addLine(to: pt(15.01, 9, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Flag

struct FlagIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.move(to: pt(4, 15, sx, sy))
            p.addCurve(to: pt(8, 14, sx, sy), control1: pt(5, 14, sx, sy), control2: pt(6, 14, sx, sy))
            p.addCurve(to: pt(16, 16, sx, sy), control1: pt(13, 16, sx, sy), control2: pt(11, 16, sx, sy))
            p.addCurve(to: pt(20, 15, sx, sy), control1: pt(18, 14, sx, sy), control2: pt(19, 14, sx, sy))
            p.addLine(to: pt(20, 3, sx, sy))
            p.addCurve(to: pt(16, 4, sx, sy), control1: pt(19, 4, sx, sy), control2: pt(18, 4, sx, sy))
            p.addCurve(to: pt(8, 2, sx, sy), control1: pt(11, 2, sx, sy), control2: pt(13, 2, sx, sy))
            p.addCurve(to: pt(4, 3, sx, sy), control1: pt(6, 3, sx, sy), control2: pt(5, 3, sx, sy))
            p.closeSubpath()
            p.move(to: pt(4, 22, sx, sy)); p.addLine(to: pt(4, 15, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - BirdwatchCheck (filled circle + checkmark)

struct BirdwatchCheckIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var circle = Path()
            circle.addEllipse(in: CGRect(x: 2 * sx, y: 2 * sy, width: 20 * sx, height: 20 * sy))
            ctx.fill(circle, with: .foreground)
            var check = Path()
            check.move(to: pt(10, 17, sx, sy))
            check.addLine(to: pt(5, 12, sx, sy)); check.addLine(to: pt(6.41, 10.59, sx, sy))
            check.addLine(to: pt(10, 14.17, sx, sy)); check.addLine(to: pt(17.59, 6.59, sx, sy))
            check.addLine(to: pt(19, 8, sx, sy)); check.addLine(to: pt(10, 17, sx, sy))
            check.closeSubpath()
            // Punch out the checkmark area to show background
            ctx.blendMode = .destinationOut
            ctx.fill(check, with: .color(.white))
        }
    }
}

// MARK: - Block (circle + slash)

struct BlockIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.addEllipse(in: CGRect(x: 2 * sx, y: 2 * sy, width: 20 * sx, height: 20 * sy))
            p.move(to: pt(4.93, 4.93, sx, sy)); p.addLine(to: pt(19.07, 19.07, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Trash

struct TrashIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.move(to: pt(3, 6, sx, sy)); p.addLine(to: pt(21, 6, sx, sy))
            p.move(to: pt(19, 6, sx, sy)); p.addLine(to: pt(19, 20, sx, sy))
            p.addQuadCurve(to: pt(17, 22, sx, sy), control: pt(19, 22, sx, sy))
            p.addLine(to: pt(7, 22, sx, sy))
            p.addQuadCurve(to: pt(5, 20, sx, sy), control: pt(5, 22, sx, sy))
            p.addLine(to: pt(5, 6, sx, sy))
            p.move(to: pt(8, 6, sx, sy)); p.addLine(to: pt(8, 4, sx, sy))
            p.addQuadCurve(to: pt(10, 2, sx, sy), control: pt(8, 2, sx, sy))
            p.addLine(to: pt(14, 2, sx, sy))
            p.addQuadCurve(to: pt(16, 4, sx, sy), control: pt(16, 2, sx, sy))
            p.addLine(to: pt(16, 6, sx, sy))
            p.move(to: pt(10, 11, sx, sy)); p.addLine(to: pt(10, 17, sx, sy))
            p.move(to: pt(14, 11, sx, sy)); p.addLine(to: pt(14, 17, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Edit (doc + pencil)

struct EditIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            // Document
            p.move(to: pt(11, 4, sx, sy)); p.addLine(to: pt(4, 4, sx, sy))
            p.addQuadCurve(to: pt(2, 6, sx, sy), control: pt(2, 4, sx, sy))
            p.addLine(to: pt(2, 20, sx, sy))
            p.addQuadCurve(to: pt(4, 22, sx, sy), control: pt(2, 22, sx, sy))
            p.addLine(to: pt(18, 22, sx, sy))
            p.addQuadCurve(to: pt(20, 20, sx, sy), control: pt(20, 22, sx, sy))
            p.addLine(to: pt(20, 13, sx, sy))
            // Pencil
            p.move(to: pt(18.5, 2.5, sx, sy))
            p.addQuadCurve(to: pt(21.5, 5.5, sx, sy), control: pt(20.6, 2.5, sx, sy))
            p.addLine(to: pt(12, 15, sx, sy)); p.addLine(to: pt(8, 16, sx, sy))
            p.addLine(to: pt(9, 12, sx, sy)); p.addLine(to: pt(18.5, 2.5, sx, sy))
            p.closeSubpath()
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - QRCode

struct QRCodeIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            let lw: CGFloat = 1.8 * min(sx, sy)
            let style = StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)
            // Top-left block
            var tl = Path()
            tl.addRect(CGRect(x: 2 * sx, y: 2 * sy, width: 8 * sx, height: 8 * sy))
            ctx.stroke(tl, with: .foreground, style: style)
            var tld = Path()
            tld.addRect(CGRect(x: 4 * sx, y: 4 * sy, width: 4 * sx, height: 4 * sy))
            ctx.fill(tld, with: .foreground)
            // Top-right block
            var tr = Path()
            tr.addRect(CGRect(x: 14 * sx, y: 2 * sy, width: 8 * sx, height: 8 * sy))
            ctx.stroke(tr, with: .foreground, style: style)
            var trd = Path()
            trd.addRect(CGRect(x: 16 * sx, y: 4 * sy, width: 4 * sx, height: 4 * sy))
            ctx.fill(trd, with: .foreground)
            // Bottom-left block
            var bl = Path()
            bl.addRect(CGRect(x: 2 * sx, y: 14 * sy, width: 8 * sx, height: 8 * sy))
            ctx.stroke(bl, with: .foreground, style: style)
            var bld = Path()
            bld.addRect(CGRect(x: 4 * sx, y: 16 * sy, width: 4 * sx, height: 4 * sy))
            ctx.fill(bld, with: .foreground)
            // Bottom-right data
            var br = Path()
            br.addRect(CGRect(x: 14 * sx, y: 14 * sy, width: 2 * sx, height: 2 * sy))
            br.addRect(CGRect(x: 18 * sx, y: 14 * sy, width: 4 * sx, height: 2 * sy))
            br.addRect(CGRect(x: 14 * sx, y: 18 * sy, width: 8 * sx, height: 4 * sy))
            ctx.fill(br, with: .foreground)
        }
    }
}

// MARK: - Verified (green circle + white checkmark)

struct VerifiedIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            // Green circle
            var circle = Path()
            circle.addEllipse(in: CGRect(x: 2 * sx, y: 2 * sy, width: 20 * sx, height: 20 * sy))
            ctx.fill(circle, with: .color(NuruColors.lineGreen))
            // White checkmark
            var check = Path()
            check.move(to: pt(7, 12, sx, sy))
            check.addLine(to: pt(10.5, 15.5, sx, sy))
            check.addLine(to: pt(17, 9, sx, sy))
            ctx.stroke(check, with: .color(.white), style: StrokeStyle(lineWidth: 2.2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Like (thumbs up)

struct LikeIcon: View {
    let filled: Bool
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            // Thumb
            p.move(to: pt(14, 9, sx, sy)); p.addLine(to: pt(14, 5, sx, sy))
            p.addQuadCurve(to: pt(11, 2, sx, sy), control: pt(14, 2, sx, sy))
            p.addLine(to: pt(7, 11, sx, sy)); p.addLine(to: pt(7, 22, sx, sy))
            p.addLine(to: pt(18.28, 22, sx, sy))
            p.addQuadCurve(to: pt(20.28, 20.3, sx, sy), control: pt(19.28, 22, sx, sy))
            p.addLine(to: pt(21.66, 11.3, sx, sy))
            p.addQuadCurve(to: pt(19.66, 9, sx, sy), control: pt(21.96, 9.5, sx, sy))
            p.addLine(to: pt(14, 9, sx, sy))
            p.closeSubpath()
            // Palm pad
            p.move(to: pt(7, 22, sx, sy)); p.addLine(to: pt(4, 22, sx, sy))
            p.addQuadCurve(to: pt(2, 20, sx, sy), control: pt(2, 22, sx, sy))
            p.addLine(to: pt(2, 13, sx, sy))
            p.addQuadCurve(to: pt(4, 11, sx, sy), control: pt(2, 11, sx, sy))
            p.addLine(to: pt(7, 11, sx, sy))
            if filled {
                ctx.fill(p, with: .foreground)
            }
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 1.8 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Bookmark

struct BookmarkIcon: View {
    let filled: Bool
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.move(to: pt(19, 21, sx, sy)); p.addLine(to: pt(12, 16, sx, sy)); p.addLine(to: pt(5, 21, sx, sy))
            p.addLine(to: pt(5, 5, sx, sy))
            p.addQuadCurve(to: pt(7, 3, sx, sy), control: pt(5, 3, sx, sy))
            p.addLine(to: pt(17, 3, sx, sy))
            p.addQuadCurve(to: pt(19, 5, sx, sy), control: pt(19, 3, sx, sy))
            p.closeSubpath()
            if filled {
                ctx.fill(p, with: .foreground)
            }
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 1.8 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Zap (lightning bolt)

struct ZapIcon: View {
    let filled: Bool
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.move(to: pt(13, 2, sx, sy)); p.addLine(to: pt(3, 14, sx, sy))
            p.addLine(to: pt(12, 14, sx, sy)); p.addLine(to: pt(11, 22, sx, sy))
            p.addLine(to: pt(21, 10, sx, sy)); p.addLine(to: pt(12, 10, sx, sy))
            p.closeSubpath()
            if filled {
                ctx.fill(p, with: .foreground)
            }
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 1.8 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Mute (speaker slash)

struct MuteIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            // Speaker body
            p.move(to: pt(11, 5, sx, sy)); p.addLine(to: pt(6, 9, sx, sy)); p.addLine(to: pt(2, 9, sx, sy))
            p.addLine(to: pt(2, 15, sx, sy)); p.addLine(to: pt(6, 15, sx, sy)); p.addLine(to: pt(11, 19, sx, sy))
            p.closeSubpath()
            // Slash
            p.move(to: pt(23, 9, sx, sy)); p.addLine(to: pt(17, 15, sx, sy))
            p.move(to: pt(17, 9, sx, sy)); p.addLine(to: pt(23, 15, sx, sy))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 2 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Home (house — no chimney)

struct HomeIcon: View {
    let filled: Bool
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            if filled {
                var p = Path()
                p.move(to: pt(12, 2, sx, sy))
                p.addLine(to: pt(3, 9, sx, sy)); p.addLine(to: pt(3, 21, sx, sy))
                p.addQuadCurve(to: pt(4, 22, sx, sy), control: pt(3, 22, sx, sy))
                p.addLine(to: pt(9, 22, sx, sy))
                p.addQuadCurve(to: pt(10, 21, sx, sy), control: pt(10, 22, sx, sy))
                p.addLine(to: pt(10, 16, sx, sy))
                p.addQuadCurve(to: pt(11, 15, sx, sy), control: pt(10, 15, sx, sy))
                p.addLine(to: pt(13, 15, sx, sy))
                p.addQuadCurve(to: pt(14, 16, sx, sy), control: pt(14, 15, sx, sy))
                p.addLine(to: pt(14, 21, sx, sy))
                p.addQuadCurve(to: pt(15, 22, sx, sy), control: pt(14, 22, sx, sy))
                p.addLine(to: pt(20, 22, sx, sy))
                p.addQuadCurve(to: pt(21, 21, sx, sy), control: pt(21, 22, sx, sy))
                p.addLine(to: pt(21, 9, sx, sy)); p.addLine(to: pt(12, 2, sx, sy))
                p.closeSubpath()
                ctx.fill(p, with: .foreground)
            } else {
                var p = Path()
                p.move(to: pt(3, 9, sx, sy)); p.addLine(to: pt(12, 2, sx, sy)); p.addLine(to: pt(21, 9, sx, sy))
                p.addLine(to: pt(21, 20, sx, sy))
                p.addQuadCurve(to: pt(19, 22, sx, sy), control: pt(21, 22, sx, sy))
                p.addLine(to: pt(5, 22, sx, sy))
                p.addQuadCurve(to: pt(3, 20, sx, sy), control: pt(3, 22, sx, sy))
                p.addLine(to: pt(3, 9, sx, sy))
                p.closeSubpath()
                ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 1.8 * min(sx, sy), lineCap: .round, lineJoin: .round))
                var door = Path()
                door.move(to: pt(9, 22, sx, sy)); door.addLine(to: pt(9, 12, sx, sy))
                door.addLine(to: pt(15, 12, sx, sy)); door.addLine(to: pt(15, 22, sx, sy))
                ctx.stroke(door, with: .foreground, style: StrokeStyle(lineWidth: 1.8 * min(sx, sy), lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Talk (chat bubble)

struct TalkIcon: View {
    let filled: Bool
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.move(to: pt(21, 11.5, sx, sy))
            p.addQuadCurve(to: pt(20.1, 15.3, sx, sy), control: pt(21, 13.5, sx, sy))
            p.addQuadCurve(to: pt(12.5, 20, sx, sy), control: pt(19, 18.5, sx, sy))
            p.addQuadCurve(to: pt(8.7, 19.1, sx, sy), control: pt(10.5, 20, sx, sy))
            p.addLine(to: pt(3, 21, sx, sy)); p.addLine(to: pt(4.9, 15.3, sx, sy))
            p.addQuadCurve(to: pt(4, 11.5, sx, sy), control: pt(4, 13.5, sx, sy))
            p.addQuadCurve(to: pt(8.7, 3.9, sx, sy), control: pt(4, 7, sx, sy))
            p.addQuadCurve(to: pt(12.5, 3, sx, sy), control: pt(10.5, 3, sx, sy))
            p.addLine(to: pt(13, 3, sx, sy))
            p.addQuadCurve(to: pt(21, 11, sx, sy), control: pt(18, 3.5, sx, sy))
            p.addLine(to: pt(21, 11.5, sx, sy))
            p.closeSubpath()
            if filled { ctx.fill(p, with: .foreground) }
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 1.8 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Timeline (calendar/newspaper)

struct TimelineIcon: View {
    let filled: Bool
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            if filled {
                // Filled: outer rectangle + inner lines
                var outer = Path()
                outer.move(to: pt(4, 4, sx, sy)); outer.addLine(to: pt(20, 4, sx, sy))
                outer.addQuadCurve(to: pt(22, 6, sx, sy), control: pt(22, 4, sx, sy))
                outer.addLine(to: pt(22, 18, sx, sy))
                outer.addQuadCurve(to: pt(20, 20, sx, sy), control: pt(22, 20, sx, sy))
                outer.addLine(to: pt(4, 20, sx, sy))
                outer.addQuadCurve(to: pt(2, 18, sx, sy), control: pt(2, 20, sx, sy))
                outer.addLine(to: pt(2, 6, sx, sy))
                outer.addQuadCurve(to: pt(4, 4, sx, sy), control: pt(2, 4, sx, sy))
                outer.closeSubpath()
                ctx.fill(outer, with: .foreground)
                // Cutout lines in background color
                let bg = Color.black
                var lines = Path()
                lines.addRect(CGRect(x: 6 * sx, y: 8 * sy, width: 4 * sx, height: 2 * sy))
                lines.addRect(CGRect(x: 6 * sx, y: 12 * sy, width: 8 * sx, height: 2 * sy))
                lines.addRect(CGRect(x: 6 * sx, y: 16 * sy, width: 6 * sx, height: 2 * sy))
                lines.addRect(CGRect(x: 16 * sx, y: 8 * sy, width: 2 * sx, height: 10 * sy))
                ctx.blendMode = .destinationOut
                ctx.fill(lines, with: .color(bg))
            } else {
                // Outline calendar
                var p = Path()
                p.move(to: pt(19, 20, sx, sy)); p.addLine(to: pt(5, 20, sx, sy))
                p.addQuadCurve(to: pt(3, 18, sx, sy), control: pt(3, 20, sx, sy))
                p.addLine(to: pt(3, 6, sx, sy))
                p.addQuadCurve(to: pt(5, 4, sx, sy), control: pt(3, 4, sx, sy))
                p.addLine(to: pt(19, 4, sx, sy))
                p.addQuadCurve(to: pt(21, 6, sx, sy), control: pt(21, 4, sx, sy))
                p.addLine(to: pt(21, 18, sx, sy))
                p.addQuadCurve(to: pt(19, 20, sx, sy), control: pt(21, 20, sx, sy))
                p.closeSubpath()
                p.move(to: pt(16, 2, sx, sy)); p.addLine(to: pt(16, 6, sx, sy))
                p.move(to: pt(8, 2, sx, sy)); p.addLine(to: pt(8, 6, sx, sy))
                p.move(to: pt(3, 10, sx, sy)); p.addLine(to: pt(21, 10, sx, sy))
                ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 1.8 * min(sx, sy), lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Grid (2×2 squares)

struct GridIcon: View {
    let filled: Bool
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            p.addRect(CGRect(x: 4 * sx, y: 4 * sy, width: 6 * sx, height: 6 * sy))
            p.addRect(CGRect(x: 14 * sx, y: 4 * sy, width: 6 * sx, height: 6 * sy))
            p.addRect(CGRect(x: 4 * sx, y: 14 * sy, width: 6 * sx, height: 6 * sy))
            p.addRect(CGRect(x: 14 * sx, y: 14 * sy, width: 6 * sx, height: 6 * sy))
            if filled { ctx.fill(p, with: .foreground) }
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 1.8 * min(sx, sy), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Bitcoin (official ₿ logo)

struct BitcoinIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 24
            let circle = Path(ellipseIn: CGRect(x: 2 * sx, y: 2 * sy, width: 20 * sx, height: 20 * sy))
            ctx.stroke(circle, with: .foreground, lineWidth: 1.5 * min(sx, sy))

            var b = Path()
            b.move(to: pt(16.916, 10.468, sx, sy))
            b.addCurve(to: pt(14.379, 7.557, sx, sy), control1: pt(17.146, 8.933, sx, sy), control2: pt(15.977, 8.108, sx, sy))
            b.addLine(to: pt(14.897, 5.478, sx, sy)); b.addLine(to: pt(13.631, 5.162, sx, sy))
            b.addLine(to: pt(13.127, 7.187, sx, sy))
            b.addCurve(to: pt(12.112, 6.948, sx, sy), control1: pt(12.794, 7.104, sx, sy), control2: pt(12.452, 7.026, sx, sy))
            b.addLine(to: pt(12.621, 4.910, sx, sy)); b.addLine(to: pt(11.356, 4.595, sx, sy))
            b.addLine(to: pt(10.837, 6.674, sx, sy))
            b.addCurve(to: pt(10.028, 6.484, sx, sy), control1: pt(10.561, 6.611, sx, sy), control2: pt(10.291, 6.549, sx, sy))
            b.addLine(to: pt(10.030, 6.477, sx, sy)); b.addLine(to: pt(8.284, 6.041, sx, sy))
            b.addLine(to: pt(7.947, 7.393, sx, sy))
            b.addCurve(to: pt(8.867, 7.622, sx, sy), control1: pt(7.947, 7.393, sx, sy), control2: pt(8.887, 7.609, sx, sy))
            b.addCurve(to: pt(9.457, 8.358, sx, sy), control1: pt(9.379, 7.750, sx, sy), control2: pt(9.472, 8.089, sx, sy))
            b.addLine(to: pt(8.866, 10.727, sx, sy))
            b.addCurve(to: pt(8.998, 10.769, sx, sy), control1: pt(8.901, 10.736, sx, sy), control2: pt(8.947, 10.749, sx, sy))
            b.addCurve(to: pt(8.864, 10.736, sx, sy), control1: pt(8.955, 10.759, sx, sy), control2: pt(8.910, 10.747, sx, sy))
            b.addLine(to: pt(8.036, 14.055, sx, sy))
            b.addCurve(to: pt(7.456, 14.356, sx, sy), control1: pt(7.973, 14.211, sx, sy), control2: pt(7.814, 14.444, sx, sy))
            b.addCurve(to: pt(6.536, 14.126, sx, sy), control1: pt(7.469, 14.374, sx, sy), control2: pt(6.536, 14.126, sx, sy))
            b.addLine(to: pt(5.907, 15.575, sx, sy)); b.addLine(to: pt(7.555, 15.986, sx, sy))
            b.addCurve(to: pt(8.457, 16.219, sx, sy), control1: pt(7.861, 16.062, sx, sy), control2: pt(8.162, 16.143, sx, sy))
            b.addLine(to: pt(7.933, 18.322, sx, sy)); b.addLine(to: pt(9.198, 18.637, sx, sy))
            b.addLine(to: pt(9.717, 16.556, sx, sy))
            b.addCurve(to: pt(10.725, 16.818, sx, sy), control1: pt(10.062, 16.650, sx, sy), control2: pt(10.397, 16.737, sx, sy))
            b.addLine(to: pt(10.208, 18.889, sx, sy)); b.addLine(to: pt(11.474, 19.205, sx, sy))
            b.addLine(to: pt(11.998, 17.106, sx, sy))
            b.addCurve(to: pt(16.463, 15.397, sx, sy), control1: pt(14.157, 17.514, sx, sy), control2: pt(15.780, 17.349, sx, sy))
            b.addCurve(to: pt(15.300, 12.327, sx, sy), control1: pt(17.013, 13.825, sx, sy), control2: pt(16.436, 12.918, sx, sy))
            b.addCurve(to: pt(16.916, 10.468, sx, sy), control1: pt(16.127, 11.136, sx, sy), control2: pt(16.750, 11.592, sx, sy))
            b.closeSubpath()
            // Lower bump
            b.move(to: pt(14.024, 14.524, sx, sy))
            b.addCurve(to: pt(10.128, 15.033, sx, sy), control1: pt(13.633, 16.096, sx, sy), control2: pt(10.986, 15.246, sx, sy))
            b.addLine(to: pt(10.823, 12.247, sx, sy))
            b.addCurve(to: pt(14.024, 14.524, sx, sy), control1: pt(11.681, 12.461, sx, sy), control2: pt(14.433, 12.885, sx, sy))
            b.closeSubpath()
            // Upper bump
            b.move(to: pt(14.415, 10.446, sx, sy))
            b.addCurve(to: pt(11.141, 10.971, sx, sy), control1: pt(14.059, 11.876, sx, sy), control2: pt(11.856, 11.149, sx, sy))
            b.addLine(to: pt(11.771, 8.444, sx, sy))
            b.addCurve(to: pt(14.415, 10.446, sx, sy), control1: pt(12.486, 8.622, sx, sy), control2: pt(14.787, 8.954, sx, sy))
            b.closeSubpath()
            ctx.fill(b, with: .foreground)
        }
    }
}
