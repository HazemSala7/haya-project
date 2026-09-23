"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { ApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { Button, ErrorNote, Field, Input } from "@/components/ui";

/**
 * Three kinds of people sign in here and the demo accounts are printed on the
 * page, as they are across these systems — a product that asks for your email
 * before it will show you anything is a product with something to hide.
 */
const BASE_PATH = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

const DEMO = [
  { label: "الإدارة", email: "admin@haya.test" },
  { label: "أخصائية نطق", email: "rana@haya.test" },
  { label: "ولي أمر", email: "sanaa@haya.test" },
];

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

  function useDemo(demoEmail: string) {
    setEmail(demoEmail);
    setPassword("password");
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

        <div className="mt-5 rounded-2xl border border-line bg-panel/85 p-4 shadow-card backdrop-blur">
          <p className="text-xs font-semibold text-muted">
            حسابات التجربة — كلمة المرور <span dir="ltr" className="font-bold text-ink">password</span>
          </p>
          <div className="mt-2.5 grid gap-1.5">
            {DEMO.map((account) => (
              <button
                key={account.email}
                type="button"
                onClick={() => useDemo(account.email)}
                className="group flex items-center justify-between gap-2 rounded-lg border border-line bg-panel px-3 py-2 text-right text-xs transition hover:border-brand/50 hover:bg-brand-soft hover:shadow-soft"
              >
                <span className="font-bold text-ink">{account.label}</span>
                <span dir="ltr" className="text-muted transition group-hover:text-brand">
                  {account.email}
                </span>
              </button>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
