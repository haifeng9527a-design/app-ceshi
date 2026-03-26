-- 管理员永久锁定：后台可手动锁定/解锁账户，与密码错误临时锁定区分

alter table public.admin_users add column if not exists permanently_locked boolean not null default false;

comment on column public.admin_users.permanently_locked is '后台永久锁定，true 时无法登录';
