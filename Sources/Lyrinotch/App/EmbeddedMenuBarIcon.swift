import AppKit
import Foundation

enum EmbeddedMenuBarIcon {
    /// 36×36 (@2x) PNG, base64 — always available even if bundles fail.
    private static let base64 = """
iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAADW0lEQVR4nO2XWYiOURjHf998s5vs2QYZMTIl++4C5c5WYywX5EZp7iRFU4SLoUhuuZDkgkKucCVrlFCWUmYITZHGln3me3X0f6Yzx/t+i7hh/vX2fu8553nO8/yf5ZwPetCDfwypLONFOWQzQPQbsklyiUjz95EulKHeQC1QlsXLu8DnQJfzfAhQEzPu8BV4DLwPxhNpdu8m4I0WR1meLZItlZw5dz+HXDuwWWt/CW3Km3BeHwI2AK3AKeCt54X/jjT/FOgMdCwHJut3sd62VyWwEhgBbAP2KHymo1s8F2ij80Av8kcdcC5LeEP0F4vfgGFxTDkvHI7Im/H6dhvYXBKWAe/kyDg55xu2EBggPSVAucbXSmZ1YEM3Ssco6Z6IXkdjB7ARWKMQtUqxM7oemAI8APoCs4BHknO6dsvI+V6pZ6S7Td8D47w0uq4BH4EKfTtvU9roZkxyvgR2yevTwAfgAvBQVXRS1ernqqXHIuA70BjHUAhLXvPqBjBTiVirxHwhZlweOOwFngF9gCvAGc2TUN6WDqX5MFQeU4GpOEGPxXzn7LsKOAxMDGzIyyC/T5Urp8YGvSctj6sUhlEaTzJ2PzAnKUr5GJTWe5Lo3xcos/nZmm+K2cz09Vb+ROp5vnzOAzSEVaSrPnLkXwgzqJ9nkGvE61WZ6UIYMjihFUpwP2QGJ7tK51kSy1PlUIeM+qJi6bKlEINCFHtPrvVmUL360DTguow6YPoKCVmxV+KnVeIdgbfrgNve0WMsWqd2Ro1Un7oFLFann6H1mVxHgw/rskf1uI5+CWhRdc3TtWO7wlDkNVEzGoX7uebb1XQNRT7V7WpUlUo6N+4nZ6Qx14mnA0uBJcAE4BNwXIa2eTojnWUNwGAd3MO1JiPWqr2q/FkUxlKjBrbyZ5BSeFo8pjplvO0xF9hh7JgxnRI+BmwCmtXaTyjJTVkIlw+vdSA7ZUO948Yx/EolPVo3yxLNVejocbijYgqj0VVpdTqDojyfy5JrjpkbpOuJnfKW+JHCbCx2q04LV0ZGWX40qLX38gR92Pqr+r6oZM14zDlWzgIHddyU6UawE7jn3TCzotDOnQvmSI2qsDoYTxQIx/L9KxQpB4tinLEyD5nIykw+3fhPwK4wlk896MH/gx+WcvYkEKdBaQAAAABJRU5ErkJggg==
"""

    static func nsImage() -> NSImage? {
        let cleaned = base64.filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: cleaned),
              let image = NSImage(data: data) else {
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}
