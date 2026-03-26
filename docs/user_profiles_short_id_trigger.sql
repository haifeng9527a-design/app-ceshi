-- short_id 由数据库生成并保证唯一，客户端不再循环随机重试。
-- 执行前需已存在 public.user_profiles.short_id 列（见 user_profile_short_id.sql）。

-- 1) 唯一约束：非空 short_id 全局唯一（多行可为 null）
drop index if exists public.user_profiles_short_id_idx;
alter table public.user_profiles
  drop constraint if exists user_profiles_short_id_key;
create unique index user_profiles_short_id_idx
  on public.user_profiles (short_id) where short_id is not null;
comment on index public.user_profiles_short_id_idx is 'short_id 唯一，由 trigger 生成';

-- 2) 6 位字符集：排除 0/O/1/I，避免歧义
create or replace function public.gen_short_id()
returns text
language plpgsql
as $$
declare
  chars text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  result text := '';
  i int;
begin
  for i in 1..6 loop
    result := result || substr(chars, 1 + floor(random() * length(chars))::int, 1);
  end loop;
  return result;
end;
$$;

-- 3) 格式约束：6 位，仅允许上述字符集
alter table public.user_profiles
  drop constraint if exists user_profiles_short_id_format;
alter table public.user_profiles
  add constraint user_profiles_short_id_format
  check (short_id is null or short_id ~ '^[2-9A-HJ-NP-Z]{6}$');

-- 4) trigger：short_id 为空时自动生成，冲突重试最多 20 次
create or replace function public.user_profiles_set_short_id()
returns trigger
language plpgsql
as $$
declare
  candidate text;
  attempts int := 0;
begin
  if new.short_id is not null and trim(new.short_id) <> '' then
    return new;
  end if;
  loop
    candidate := public.gen_short_id();
    if not exists (
      select 1 from public.user_profiles
      where short_id = candidate
        and (tg_op = 'INSERT' or user_id <> new.user_id)
    ) then
      new.short_id := candidate;
      return new;
    end if;
    attempts := attempts + 1;
    if attempts >= 20 then
      raise exception 'Could not generate unique short_id after 20 attempts';
    end if;
  end loop;
end;
$$;

drop trigger if exists user_profiles_set_short_id_trigger on public.user_profiles;
create trigger user_profiles_set_short_id_trigger
  before insert or update on public.user_profiles
  for each row
  execute function public.user_profiles_set_short_id();
