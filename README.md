# MedClass

A Persian, RTL learning portal built with HTML, CSS, JavaScript and Supabase.

## Features

- Email/password sign-up, sign-in, sign-out and password reset
- Student and teacher views
- Course catalogue and course enrollment
- Lesson list with optional external video/file links
- Teacher course and lesson management
- Responsive Persian RTL interface
- Supabase Row Level Security policies

## Setup

1. Open the Supabase project configured in `index.html`.
2. Open **SQL Editor** in the Supabase dashboard.
3. Paste and run the complete contents of `supabase/schema.sql`.
4. In Supabase **Authentication → URL Configuration**, add your deployed site URL to the allowed redirect URLs (for password recovery).
5. Enable email/password authentication. If email confirmation is enabled, users must confirm their email before signing in.
6. Deploy the repository with GitHub Pages or another static host.

The browser uses only the Supabase publishable/anon key. Never place a Supabase `service_role` key in frontend code.

## Create the first teacher

New public sign-ups are always created as students. This is intentional: the browser must not be allowed to grant itself teacher permissions.

After the intended teacher has registered and confirmed their email, run this in the Supabase SQL Editor, replacing the email:

```sql
update public.profiles p
set role = 'teacher'
from auth.users u
where p.id = u.id
  and u.email = 'teacher@example.com';
```

The teacher should sign out and sign in again to refresh their profile role.

## Notes

- Course and lesson content is stored in Supabase, not in browser local storage.
- Lesson links are external URLs. Uploading files to Supabase Storage is a future enhancement.
- This is a lightweight starter LMS, not a substitute for a full production review, backups, moderation, or institutional access controls.
