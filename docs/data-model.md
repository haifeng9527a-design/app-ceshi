# 数据模型（初版）

## Teacher
- id: string
- name: string
- title: string
- avatarUrl: string
- bio: string
- tags: string[]
- articles: Article[]
- schedules: ScheduleItem[]

## Article
- id: string
- title: string
- summary: string
- date: string

## ScheduleItem
- id: string
- title: string
- date: string
- location: string

## RankingEntry
- teacherId: string
- score: number
