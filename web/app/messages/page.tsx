"use client";

import Link from "next/link";
import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import { ApiError, api } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { PageHead } from "@/components/shell";
import { Badge, Button, Card, Empty, ErrorNote, Loading, Textarea } from "@/components/ui";
import { ROLE_LABELS, dateTime, dayDate, relative } from "@/lib/format";
import type { Message, Profile, Student } from "@/lib/types";

export default function MessagesPage() {
  return (
    <Suspense fallback={<Loading />}>
      <Messages />
    </Suspense>
  );
}

type Thread = {
  student_id: number;
  student_name: string;
  unread: number;
  last_at: string;
};

function Messages() {
  const { user } = useAuth();
  const params = useSearchParams();

  const [threads, setThreads] = useState<Thread[]>([]);
  const [students, setStudents] = useState<Pick<Student, "id" | "name">[]>([]);
  const [active, setActive] = useState<number | null>(
    params.get("student") ? Number(params.get("student")) : null,
  );
  const [loading, setLoading] = useState(true);

  /*
   * Two lists merged into one column: the children with something waiting,
   * and then everyone else. A parent with one child never sees a picker at
   * all — the thread opens straight away, because "choose a conversation" is
   * an absurd thing to ask someone with exactly one.
   */
  const load = useCallback(async () => {
    const [unread, mine] = await Promise.all([
      api<{ data: Thread[] }>("/messages/unread"),
      api<{ data: Pick<Student, "id" | "name">[] }>("/students", {
        query: { per_page: 100, status: "active" },
      }),
    ]);

    setThreads(unread.data);
    setStudents(mine.data);
    setLoading(false);

    setActive((current) => current ?? unread.data[0]?.student_id ?? mine.data[0]?.id ?? null);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  if (loading) return <Loading boxed rows={5} />;

  if (students.length === 0) {
    return (
      <>
        <PageHead title="الرسائل" />
        <Empty title="ما في محادثات" hint="الرسائل بتكون حول طفل مسجّل." />
      </>
    );
  }

  const unreadFor = (id: number) => threads.find((t) => t.student_id === id)?.unread ?? 0;

  return (
    <>
      <PageHead
        title="الرسائل"
        subtitle={
          user?.role === "guardian"
            ? "أسئلتك للأخصائية، وردودها — كلها هون."
            : "محادثات الأهل حول أطفالهم. كل الفريق بيشوفها."
        }
      />

      <div className="grid gap-4 lg:grid-cols-[16rem_1fr]">
        {students.length > 1 && (
          <Card title="الأطفال">
            <ul className="max-h-[28rem] divide-y divide-line overflow-y-auto">
              {students.map((student) => (
                <li key={student.id}>
                  <button
                    onClick={() => setActive(student.id)}
                    className={`flex w-full items-center justify-between gap-2 px-4 py-2.5 text-right transition ${
                      active === student.id ? "bg-brand-soft" : "hover:bg-brand-soft/45"
                    }`}
                  >
                    <span
                      className={`text-sm font-semibold ${
                        active === student.id ? "text-brand" : "text-ink"
                      }`}
                    >
                      {student.name}
                    </span>
                    {unreadFor(student.id) > 0 && (
                      <Badge className="bg-brand text-white">{unreadFor(student.id)}</Badge>
                    )}
                  </button>
                </li>
              ))}
            </ul>
          </Card>
        )}

        <div className={students.length > 1 ? "" : "lg:col-span-2"}>
          {active ? (
            <Thread
              studentId={active}
              studentName={students.find((s) => s.id === active)?.name ?? ""}
              me={user}
              onSent={load}
            />
          ) : (
            <Empty title="اختر طفلاً" />
          )}
        </div>
      </div>
    </>
  );
}

function Thread({
  studentId,
  studentName,
  me,
  onSent,
}: {
  studentId: number;
  studentName: string;
  me: Profile | null;
  onSent: () => Promise<void>;
}) {
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(true);
  const [body, setBody] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const bottom = useRef<HTMLDivElement>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const res = await api<{ data: Message[] }>(`/students/${studentId}/messages`, {
      query: { per_page: 100 },
    });
    setMessages(res.data);
    setLoading(false);
  }, [studentId]);

  useEffect(() => {
    load();
  }, [load]);

  useEffect(() => {
    bottom.current?.scrollIntoView({ block: "nearest" });
  }, [messages]);

  async function send() {
    setBusy(true);
    setError(null);

    try {
      await api(`/students/${studentId}/messages`, { method: "POST", body: { body } });
      setBody("");
      await load();
      await onSent();
    } catch (e) {
      setError((e as ApiError).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card title={studentName}>
      <div className="max-h-[26rem] space-y-3 overflow-y-auto p-4">
        {loading ? (
          <Loading />
        ) : messages.length === 0 ? (
          <Empty
            title="ما في رسائل بعد"
            hint="اكتب أول رسالة — السؤال المكتوب بيوصل الفريق كله."
          />
        ) : (
          messages.map((message) => {
            const isMine = message.sender_id === me?.id;

            return (
              <div
                key={message.id}
                className={`flex ${isMine ? "justify-start" : "justify-end"}`}
              >
                {/*
                  A squared-off corner on the side the bubble comes from, so
                  who said what is carried by shape as well as by colour and
                  side — and 72% rather than 85% on a wide screen, because a
                  600px line of Arabic is a paragraph, not a message.
                */}
                <div
                  className={`max-w-[85%] rounded-2xl px-4 py-2.5 shadow-soft sm:max-w-[72%] ${
                    isMine
                      ? "bg-gradient-to-b from-brand to-brand-deep text-white rtl:rounded-tr-md ltr:rounded-tl-md"
                      : "border border-line bg-panel text-ink rtl:rounded-tl-md ltr:rounded-tr-md"
                  }`}
                >
                  {!isMine && (
                    <p className="mb-0.5 text-xs font-bold text-brand">
                      {message.sender?.name}
                      {message.sender?.title
                        ? ` · ${message.sender.title}`
                        : message.sender?.role
                          ? ` · ${ROLE_LABELS[message.sender.role]}`
                          : ""}
                    </p>
                  )}

                  {/* A question pinned to a report arrives attached to the day
                      it is about, instead of as a bare "شو صار امبارح؟". */}
                  {message.session && (
                    <Link
                      href={`/sessions/view?id=${message.session.id}`}
                      className={`mb-1.5 block rounded-lg px-2 py-1 text-xs ${
                        isMine ? "bg-white/15" : "bg-brand-soft text-brand"
                      }`}
                    >
                      بخصوص جلسة {dayDate(message.session.scheduled_at)} ←
                    </Link>
                  )}

                  <p className="whitespace-pre-wrap text-sm leading-relaxed">{message.body}</p>

                  <p
                    className={`mt-1 text-[11px] ${isMine ? "text-white/70" : "text-muted"}`}
                  >
                    {relative(message.created_at)}
                  </p>
                </div>
              </div>
            );
          })
        )}
        <div ref={bottom} />
      </div>

      <div className="space-y-2 border-t border-line bg-surface/60 p-4">
        {error && <ErrorNote message={error} />}
        <Textarea
          rows={2}
          value={body}
          onChange={(e) => setBody(e.target.value)}
          placeholder="اكتب رسالتك…"
          className="resize-none"
        />
        <div className="flex items-center justify-between gap-3">
          <p className="text-[11px] text-muted">
            الرسالة بتوصل الفريق المسؤول عن الطفل — مش شخص واحد.
          </p>
          <Button disabled={busy || !body.trim()} onClick={send}>
            {busy ? "عم نبعت…" : "أرسل"}
          </Button>
        </div>
      </div>
    </Card>
  );
}
