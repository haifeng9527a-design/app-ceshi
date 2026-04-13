-- Migrate all existing users with old u_ prefix UIDs to 10-digit numeric UIDs
-- Temporarily disables FK constraints, updates all references, then re-enables

BEGIN;

-- Step 1: Create temp mapping table
CREATE TEMP TABLE uid_map (old_uid TEXT PRIMARY KEY, new_uid TEXT UNIQUE);

-- Step 2: Generate new numeric UIDs for all old-format users
DO $$
DECLARE
    r RECORD;
    v_new_uid TEXT;
    attempts INT;
BEGIN
    FOR r IN SELECT uid FROM users WHERE uid LIKE 'u_%' ORDER BY uid LOOP
        attempts := 0;
        LOOP
            v_new_uid := (1000000000 + floor(random() * 9000000000))::BIGINT::TEXT;
            EXIT WHEN NOT EXISTS (SELECT 1 FROM users WHERE uid = v_new_uid)
                   AND NOT EXISTS (SELECT 1 FROM uid_map WHERE uid_map.new_uid = v_new_uid);
            attempts := attempts + 1;
            IF attempts > 20 THEN
                RAISE EXCEPTION 'Failed to generate unique UID';
            END IF;
        END LOOP;
        INSERT INTO uid_map VALUES (r.uid, v_new_uid);
    END LOOP;
END $$;

-- Step 3: Temporarily drop all FK constraints referencing users(uid)
ALTER TABLE calls DROP CONSTRAINT IF EXISTS calls_initiator_id_fkey;
ALTER TABLE calls DROP CONSTRAINT IF EXISTS calls_ended_by_fkey;
ALTER TABLE conversation_members DROP CONSTRAINT IF EXISTS conversation_members_user_id_fkey;
ALTER TABLE conversations DROP CONSTRAINT IF EXISTS conversations_created_by_fkey;
ALTER TABLE copy_trading DROP CONSTRAINT IF EXISTS copy_trading_follower_id_fkey;
ALTER TABLE copy_trading DROP CONSTRAINT IF EXISTS copy_trading_trader_id_fkey;
ALTER TABLE feedbacks DROP CONSTRAINT IF EXISTS feedbacks_user_id_fkey;
ALTER TABLE friend_requests DROP CONSTRAINT IF EXISTS friend_requests_from_user_id_fkey;
ALTER TABLE friend_requests DROP CONSTRAINT IF EXISTS friend_requests_to_user_id_fkey;
ALTER TABLE friends DROP CONSTRAINT IF EXISTS friends_user_id_fkey;
ALTER TABLE friends DROP CONSTRAINT IF EXISTS friends_friend_id_fkey;
ALTER TABLE message_reads DROP CONSTRAINT IF EXISTS message_reads_user_id_fkey;
ALTER TABLE messages DROP CONSTRAINT IF EXISTS messages_sender_id_fkey;
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_user_id_fkey;
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_user_id_fkey;
ALTER TABLE positions DROP CONSTRAINT IF EXISTS positions_user_id_fkey;
ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_reporter_id_fkey;
ALTER TABLE strategy_likes DROP CONSTRAINT IF EXISTS strategy_likes_user_id_fkey;
ALTER TABLE teacher_followers DROP CONSTRAINT IF EXISTS teacher_followers_user_id_fkey;
ALTER TABLE teachers DROP CONSTRAINT IF EXISTS teachers_user_id_fkey;
ALTER TABLE trader_applications DROP CONSTRAINT IF EXISTS trader_applications_user_id_fkey;
ALTER TABLE trader_applications DROP CONSTRAINT IF EXISTS trader_applications_reviewed_by_fkey;
ALTER TABLE trader_stats DROP CONSTRAINT IF EXISTS trader_stats_user_id_fkey;
ALTER TABLE trader_strategies DROP CONSTRAINT IF EXISTS trader_strategies_author_id_fkey;
ALTER TABLE trader_strategy_likes DROP CONSTRAINT IF EXISTS trader_strategy_likes_user_id_fkey;
ALTER TABLE user_follows DROP CONSTRAINT IF EXISTS user_follows_user_id_fkey;
ALTER TABLE user_follows DROP CONSTRAINT IF EXISTS user_follows_trader_id_fkey;
ALTER TABLE wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_user_id_fkey;
ALTER TABLE wallets DROP CONSTRAINT IF EXISTS wallets_user_id_fkey;
ALTER TABLE watchlist DROP CONSTRAINT IF EXISTS watchlist_user_id_fkey;

-- Step 4: Update all tables using the mapping
UPDATE users u SET uid = m.new_uid FROM uid_map m WHERE u.uid = m.old_uid;

UPDATE calls SET initiator_id = m.new_uid FROM uid_map m WHERE initiator_id = m.old_uid;
UPDATE calls SET ended_by = m.new_uid FROM uid_map m WHERE ended_by = m.old_uid;
UPDATE conversation_members SET user_id = m.new_uid FROM uid_map m WHERE user_id = m.old_uid;
UPDATE conversations SET created_by = m.new_uid FROM uid_map m WHERE created_by = m.old_uid;
UPDATE copy_trading SET follower_id = m.new_uid FROM uid_map m WHERE follower_id = m.old_uid;
UPDATE copy_trading SET trader_id = m.new_uid FROM uid_map m WHERE trader_id = m.old_uid;
UPDATE feedbacks SET user_id = m.new_uid FROM uid_map m WHERE user_id = m.old_uid;
UPDATE friend_requests SET from_user_id = m.new_uid FROM uid_map m WHERE from_user_id = m.old_uid;
UPDATE friend_requests SET to_user_id = m.new_uid FROM uid_map m WHERE to_user_id = m.old_uid;
UPDATE friends SET user_id = m.new_uid FROM uid_map m WHERE user_id = m.old_uid;
UPDATE friends SET friend_id = m.new_uid FROM uid_map m WHERE friend_id = m.old_uid;
UPDATE message_reads SET user_id = m.new_uid FROM uid_map m WHERE user_id = m.old_uid;
UPDATE messages SET sender_id = m.new_uid FROM uid_map m WHERE sender_id = m.old_uid;
UPDATE notifications SET user_id = m.new_uid FROM uid_map m WHERE user_id = m.old_uid;
UPDATE orders SET user_id = m.new_uid FROM uid_map m WHERE user_id = m.old_uid;
UPDATE positions SET user_id = m.new_uid FROM uid_map m WHERE user_id = m.old_uid;
UPDATE reports SET reporter_id = m.new_uid FROM uid_map m WHERE reporter_id = m.old_uid;
UPDATE strategy_likes SET user_id = m.new_uid FROM uid_map m WHERE user_id = m.old_uid;
UPDATE teacher_followers SET user_id = m.new_uid FROM uid_map m WHERE user_id = m.old_uid;
UPDATE teachers SET user_id = m.new_uid FROM uid_map m WHERE user_id = m.old_uid;
UPDATE trader_applications SET user_id = m.new_uid FROM uid_map m WHERE user_id = m.old_uid;
UPDATE trader_applications SET reviewed_by = m.new_uid FROM uid_map m WHERE reviewed_by = m.old_uid;
UPDATE trader_stats SET user_id = m.new_uid FROM uid_map m WHERE user_id = m.old_uid;
UPDATE trader_strategies SET author_id = m.new_uid FROM uid_map m WHERE author_id = m.old_uid;
UPDATE trader_strategy_likes SET user_id = m.new_uid FROM uid_map m WHERE user_id = m.old_uid;
UPDATE user_follows SET user_id = m.new_uid FROM uid_map m WHERE user_id = m.old_uid;
UPDATE user_follows SET trader_id = m.new_uid FROM uid_map m WHERE trader_id = m.old_uid;
UPDATE wallet_transactions SET user_id = m.new_uid FROM uid_map m WHERE user_id = m.old_uid;
UPDATE wallets SET user_id = m.new_uid FROM uid_map m WHERE user_id = m.old_uid;
UPDATE watchlist SET user_id = m.new_uid FROM uid_map m WHERE user_id = m.old_uid;

-- Step 5: Re-add FK constraints
ALTER TABLE calls ADD CONSTRAINT calls_initiator_id_fkey FOREIGN KEY (initiator_id) REFERENCES users(uid);
ALTER TABLE calls ADD CONSTRAINT calls_ended_by_fkey FOREIGN KEY (ended_by) REFERENCES users(uid);
ALTER TABLE conversation_members ADD CONSTRAINT conversation_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(uid);
ALTER TABLE conversations ADD CONSTRAINT conversations_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(uid);
ALTER TABLE copy_trading ADD CONSTRAINT copy_trading_follower_id_fkey FOREIGN KEY (follower_id) REFERENCES users(uid);
ALTER TABLE copy_trading ADD CONSTRAINT copy_trading_trader_id_fkey FOREIGN KEY (trader_id) REFERENCES users(uid);
ALTER TABLE feedbacks ADD CONSTRAINT feedbacks_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(uid);
ALTER TABLE friend_requests ADD CONSTRAINT friend_requests_from_user_id_fkey FOREIGN KEY (from_user_id) REFERENCES users(uid);
ALTER TABLE friend_requests ADD CONSTRAINT friend_requests_to_user_id_fkey FOREIGN KEY (to_user_id) REFERENCES users(uid);
ALTER TABLE friends ADD CONSTRAINT friends_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(uid);
ALTER TABLE friends ADD CONSTRAINT friends_friend_id_fkey FOREIGN KEY (friend_id) REFERENCES users(uid);
ALTER TABLE message_reads ADD CONSTRAINT message_reads_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(uid);
ALTER TABLE messages ADD CONSTRAINT messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES users(uid);
ALTER TABLE notifications ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(uid);
ALTER TABLE orders ADD CONSTRAINT orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(uid);
ALTER TABLE positions ADD CONSTRAINT positions_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(uid);
ALTER TABLE reports ADD CONSTRAINT reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES users(uid);
ALTER TABLE strategy_likes ADD CONSTRAINT strategy_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(uid);
ALTER TABLE teacher_followers ADD CONSTRAINT teacher_followers_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(uid);
ALTER TABLE teachers ADD CONSTRAINT teachers_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(uid);
ALTER TABLE trader_applications ADD CONSTRAINT trader_applications_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(uid);
ALTER TABLE trader_applications ADD CONSTRAINT trader_applications_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES users(uid);
ALTER TABLE trader_stats ADD CONSTRAINT trader_stats_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(uid);
ALTER TABLE trader_strategies ADD CONSTRAINT trader_strategies_author_id_fkey FOREIGN KEY (author_id) REFERENCES users(uid);
ALTER TABLE trader_strategy_likes ADD CONSTRAINT trader_strategy_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(uid);
ALTER TABLE user_follows ADD CONSTRAINT user_follows_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(uid);
ALTER TABLE user_follows ADD CONSTRAINT user_follows_trader_id_fkey FOREIGN KEY (trader_id) REFERENCES users(uid);
ALTER TABLE wallet_transactions ADD CONSTRAINT wallet_transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(uid);
ALTER TABLE wallets ADD CONSTRAINT wallets_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(uid);
ALTER TABLE watchlist ADD CONSTRAINT watchlist_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(uid);

DROP TABLE uid_map;

COMMIT;
