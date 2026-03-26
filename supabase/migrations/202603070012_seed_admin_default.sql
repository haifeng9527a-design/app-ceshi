-- 插入默认管理员账号：admin / admin123
-- 密码为 bcrypt 哈希，仅当 admin 不存在时插入

insert into public.admin_users (username, password_hash, failed_attempts, locked_until)
select 'admin', '$2b$10$7WsD9QLQ08HJd4J0NU9GX.ktFViMyHqsFzMHjEdwkrTcJNjsf699e', 0, null
where not exists (select 1 from public.admin_users where username = 'admin');
