import type { Metadata } from "next";
import { AuthProvider } from "@/lib/auth";
import { Shell } from "@/components/shell";
import "./globals.css";

export const metadata: Metadata = {
  title: "أكاديمية الحياة للتأهيل",
  description:
    "متابعة الأطفال في برامج التأهيل: الجلسات، الأهداف العلاجية، والتقرير اليومي الذي يصل ولي الأمر.",
  // The academy's own mark, cut from the logo — see public/icon.png.
  icons: { icon: `${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}/icon.png` },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ar" dir="rtl">
      <head>
        {/*
          Cairo. `display=swap` shows the fallback immediately rather than
          holding the screen blank waiting for a font — a parent on a phone on
          a bad connection gets the report, not a white page.
        */}
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link
          href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;500;600;700;800&display=swap"
          rel="stylesheet"
        />
      </head>
      {/*
        suppressHydrationWarning: password managers and other extensions add
        attributes to <body> before React hydrates, which React reports as a
        mismatch. It is their markup, not ours, and nothing below this element
        is suppressed.
      */}
      <body suppressHydrationWarning>
        <AuthProvider>
          <Shell>{children}</Shell>
        </AuthProvider>
      </body>
    </html>
  );
}
