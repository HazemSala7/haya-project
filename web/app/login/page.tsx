"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { ApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { Button, ErrorNote, Field, Input } from "@/components/ui";

/**
 * Three kinds of people sign in here — the office, a specialist, and a mother.
 *
 * ---------------------------------------------------------------------------
 * There are no demo accounts printed on this page, and there used to be.
 *
 * Printing them is the right call for a product demo: a landing page that
 * asks for your email before it will show you anything is a page with
 * something to hide. It is the wrong call the moment the thing behind the
 * login stops being a demo. What is behind this one now is sixty real
 * children — their diagnoses, their sessions, their mothers' phone numbers —
 * and the academy's own staff sign in through this form. A list of working
 * usernames beside a published password is not a friendly touch there; it is
 * the front door left open with a note saying which key fits.
 *
 * If the academy ever wants a sales demo, it gets its own deployment with its
 * own invented children, and that one can print whatever it likes.
 */
const BASE_PATH = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

export default function LoginPage() {
  const { signIn } = useAuth();
  const router = useRouter();

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<ApiError | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    try {
      await signIn(email, password);
      router.replace("/");
    } catch (e) {
      setError(e as ApiError);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden px-4 py-10">
      {/*
        The logo's canopy, blown up far past the frame and softened out.
        Two blooms and a pair of open rings — the same construction as the hero
        on the first screen, so signing in already looks like the app behind it.
      */}
      <div aria-hidden className="pointer-events-none absolute inset-0 -z-10">
        <span className="absolute -top-40 -end-32 size-[34rem] rounded-full bg-sky/30 blur-3xl" />
        <span className="absolute -bottom-44 -start-28 size-[30rem] rounded-full bg-sage/30 blur-3xl" />
        <span className="absolute top-10 start-10 size-72 rounded-full border-[18px] border-panel/45" />
        <span className="absolute bottom-4 end-16 size-56 rounded-full border-[14px] border-panel/40" />
      </div>

      <div className="rise w-full max-w-sm">
        <div className="mb-6 text-center">
          {/*
            The academy's own lockup, at the size it was drawn to be read —
            this is the one screen with room for it, and the one where a parent
            signing in for the first time needs to recognise where she is.
          */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={`${BASE_PATH}/logo.png`}
            alt="أكاديمية الحياة للتأهيل"
            className="mx-auto mb-4 w-52 max-w-full"
          />
          <p className="text-sm text-muted">متابعة الطفل — جلسة بجلسة، وهدفاً بهدف.</p>
        </div>

        <form onSubmit={submit} className="sheen rounded-2xl border border-line bg-panel p-5 shadow-float">
          <div className="space-y-3">
            <Field label="البريد الإلكتروني" error={error?.for("email")}>
              <Input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                autoComplete="username"
                dir="ltr"
                className="text-left"
                required
              />
            </Field>

            <Field label="كلمة المرور" error={error?.for("password")}>
              <Input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                autoComplete="current-password"
                dir="ltr"
                className="text-left"
                required
              />
            </Field>
          </div>

          {/* The field-level errors are already under their inputs; this is for
              the ones that belong to neither field — a suspended account. */}
          {error && !error.for("email") && !error.for("password") && (
            <div className="mt-3">
              <ErrorNote message={error.message} />
            </div>
          )}

          <Button type="submit" disabled={busy} className="mt-4 w-full">
            {busy ? "لحظة…" : "دخول"}
          </Button>
        </form>

        {/* Where the account comes from, since nothing on this page offers
            one. A mother who cannot get in needs to know who to ask, not a
            «نسيت كلمة المرور» link to an inbox the academy does not run. */}
        <p className="mt-5 text-center text-xs leading-relaxed text-muted">
          الحسابات تُفتح من إدارة الأكاديمية.
          <br />
          إذا ما قدرت تدخل، راجع الإدارة لإعادة ضبط كلمة المرور.
        </p>
      </div>
    </div>
  );
}
