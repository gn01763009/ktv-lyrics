import KTVCore

extension OverlayStyle {
    /// A copy with the given fields replaced. The receiver is left unchanged.
    func replacing(
        unsungFill: RGBAColor? = nil,
        unsungStroke: RGBAColor? = nil,
        sungFill: RGBAColor? = nil,
        sungStroke: RGBAColor? = nil,
        strokeWidth: Double? = nil,
        fontName: String? = nil
    ) -> OverlayStyle {
        OverlayStyle(
            unsungFill: unsungFill ?? self.unsungFill,
            unsungStroke: unsungStroke ?? self.unsungStroke,
            sungFill: sungFill ?? self.sungFill,
            sungStroke: sungStroke ?? self.sungStroke,
            strokeWidth: strokeWidth ?? self.strokeWidth,
            fontName: fontName ?? self.fontName,
            scale: scale,
            singleLine: singleLine
        )
    }
}
