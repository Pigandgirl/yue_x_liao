package database

import (
	"context"
	"fmt"

	"github.com/redis/go-redis/v9"
)

type RedisDB struct {
	Client *redis.Client
}

func NewRedisDB(ctx context.Context, host, port, password string) (*RedisDB, error) {
	client := redis.NewClient(&redis.Options{
		Addr:         fmt.Sprintf("%s:%s", host, port),
		Password:     password,
		DB:           0,
		PoolSize:     50,
		MinIdleConns: 10,
		DialTimeout:  5 * time.Second,
		ReadTimeout:  3 * time.Second,
		WriteTimeout: 3 * time.Second,
	})

	if err := client.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("failed to connect to Redis: %w", err)
	}

	return &RedisDB{Client: client}, nil
}

func (r *RedisDB) Close() error {
	if r.Client != nil {
		return r.Client.Close()
	}
	return nil
}

func (r *RedisDB) Ping(ctx context.Context) error {
	return r.Client.Ping(ctx).Err()
}

func (r *RedisDB) SetUserOnline(ctx context.Context, userID, connectionID string) error {
	key := fmt.Sprintf("user:online:%s", userID)
	return r.Client.Set(ctx, key, connectionID, 0).Err()
}

func (r *RedisDB) SetUserOffline(ctx context.Context, userID string) error {
	key := fmt.Sprintf("user:online:%s", userID)
	return r.Client.Del(ctx, key).Err()
}

func (r *RedisDB) IsUserOnline(ctx context.Context, userID string) (bool, error) {
	key := fmt.Sprintf("user:online:%s", userID)
	result, err := r.Client.Exists(ctx, key).Result()
	if err != nil {
		return false, err
	}
	return result > 0, nil
}

func (r *RedisDB) GetUserConnectionID(ctx context.Context, userID string) (string, error) {
	key := fmt.Sprintf("user:online:%s", userID)
	return r.Client.Get(ctx, key).Result()
}

func (r *RedisDB) AddToUserSet(ctx context.Context, setKey, member string) error {
	return r.Client.SAdd(ctx, setKey, member).Err()
}

func (r *RedisDB) RemoveFromUserSet(ctx context.Context, setKey, member string) error {
	return r.Client.SRem(ctx, setKey, member).Err()
}

func (r *RedisDB) GetUserSet(ctx context.Context, setKey string) ([]string, error) {
	return r.Client.SMembers(ctx, setKey).Result()
}
