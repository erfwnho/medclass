-- MedClass database schema for Supabase
-- Run this file in Supabase Dashboard > SQL Editor.
-- IMPORTANT: never put the Supabase service_role key in index.html.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role text not null default 'student' check (role in ('student','teacher')),
  created_at timestamptz not null default now()
);

create table if not exists public.courses (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  description text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.lessons (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  title text not null,
  description text not null default '',
  video_url text,
  position integer not null default 1,
  created_at timestamptz not null default now()
);

create table if not exists public.enrollments (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(course_id, student_id)
);

-- Create a student profile automatically after every successful sign-up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    'student'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.courses enable row level security;
alter table public.lessons enable row level security;
alter table public.enrollments enable row level security;

-- Profiles: users can read/update their own profile. Role cannot be changed by
-- the client because the update policy below is supplemented by a column grant.
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select to authenticated using (id = (select auth.uid()));

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update to authenticated using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Courses are visible to signed-in users. Only teacher accounts can create,
-- update or delete their own courses.
drop policy if exists "courses_read_authenticated" on public.courses;
create policy "courses_read_authenticated" on public.courses
  for select to authenticated using (true);

drop policy if exists "courses_teacher_insert" on public.courses;
create policy "courses_teacher_insert" on public.courses
  for insert to authenticated
  with check (
    teacher_id = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.role = 'teacher'
    )
  );

drop policy if exists "courses_teacher_update" on public.courses;
create policy "courses_teacher_update" on public.courses
  for update to authenticated
  using (
    teacher_id = (select auth.uid())
    and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'teacher')
  )
  with check (
    teacher_id = (select auth.uid())
    and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'teacher')
  );

drop policy if exists "courses_teacher_delete" on public.courses;
create policy "courses_teacher_delete" on public.courses
  for delete to authenticated
  using (
    teacher_id = (select auth.uid())
    and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'teacher')
  );

-- Lessons: enrolled students and the owning teacher can read; only owning
-- teachers can manage lesson content.
drop policy if exists "lessons_read_enrolled_or_teacher" on public.lessons;
create policy "lessons_read_enrolled_or_teacher" on public.lessons
  for select to authenticated using (
    exists (
      select 1 from public.courses c
      where c.id = course_id
      and (
        c.teacher_id = (select auth.uid())
        or exists (
          select 1 from public.enrollments e
          where e.course_id = c.id and e.student_id = (select auth.uid())
        )
      )
    )
  );

drop policy if exists "lessons_teacher_insert" on public.lessons;
create policy "lessons_teacher_insert" on public.lessons
  for insert to authenticated with check (
    exists (select 1 from public.courses c where c.id = course_id and c.teacher_id = (select auth.uid()))
  );

drop policy if exists "lessons_teacher_update" on public.lessons;
create policy "lessons_teacher_update" on public.lessons
  for update to authenticated
  using (exists (select 1 from public.courses c where c.id = course_id and c.teacher_id = (select auth.uid())))
  with check (exists (select 1 from public.courses c where c.id = course_id and c.teacher_id = (select auth.uid())));

drop policy if exists "lessons_teacher_delete" on public.lessons;
create policy "lessons_teacher_delete" on public.lessons
  for delete to authenticated
  using (exists (select 1 from public.courses c where c.id = course_id and c.teacher_id = (select auth.uid())));

-- Students can enroll themselves. They can read only their own enrollments.
drop policy if exists "enrollments_read_own_or_teacher" on public.enrollments;
create policy "enrollments_read_own_or_teacher" on public.enrollments
  for select to authenticated using (
    student_id = (select auth.uid())
    or exists (select 1 from public.courses c where c.id = course_id and c.teacher_id = (select auth.uid()))
  );

drop policy if exists "enrollments_student_insert" on public.enrollments;
create policy "enrollments_student_insert" on public.enrollments
  for insert to authenticated with check (student_id = (select auth.uid()));

drop policy if exists "enrollments_student_delete" on public.enrollments;
create policy "enrollments_student_delete" on public.enrollments
  for delete to authenticated using (student_id = (select auth.uid()));

-- Backfill profiles for users who registered before this trigger was installed.
insert into public.profiles (id, full_name, role)
select id, coalesce(raw_user_meta_data ->> 'full_name', ''), 'student'
from auth.users
on conflict (id) do nothing;

-- Keep profile roles protected from browser-side escalation.
revoke update on public.profiles from authenticated;
grant update (full_name) on public.profiles to authenticated;
grant select on public.profiles to authenticated;
grant select, insert, update, delete on public.courses to authenticated;
grant select, insert, update, delete on public.lessons to authenticated;
grant select, insert, delete on public.enrollments to authenticated;

-- Promote a trusted account to teacher only from this SQL editor, after
-- replacing the email below with the intended teacher's verified email:
-- update public.profiles p
-- set role = 'teacher'
-- from auth.users u
-- where p.id = u.id and u.email = 'teacher@example.com';
