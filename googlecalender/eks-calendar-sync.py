#!/usr/bin/env python3
"""
EKS 프로젝트 일정을 Google Calendar에 자동으로 등록하는 스크립트

사용 방법:
1. Google Cloud Console에서 Calendar API 활성화
2. OAuth 2.0 클라이언트 ID 생성 (credentials.json 다운로드)
3. pip install google-auth-oauthlib google-auth-httplib2 google-api-python-client
4. python eks-calendar-sync.py
"""

from datetime import datetime, timedelta
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
import os.path
import pickle

# Google Calendar API 스코프
SCOPES = ['https://www.googleapis.com/auth/calendar']

# 이벤트 데이터
EVENTS = [
    # EKS 구축
    {
        'summary': '🏗️ EKS 구축 - PRISM STG',
        'description': 'PRISM STG 환경 EKS 클러스터 구축',
        'start': '2026-01-27',
        'end': '2026-01-27',
        'colorId': '9',  # 파란색
        'category': '구축'
    },
    {
        'summary': '🏗️ EKS 구축 - CMAS STG',
        'description': 'CMAS STG 환경 EKS 클러스터 구축',
        'start': '2026-02-17',
        'end': '2026-02-17',
        'colorId': '9',
        'category': '구축'
    },
    {
        'summary': '🏗️ EKS 구축 - PRISM PRD',
        'description': 'PRISM PRD 환경 EKS 클러스터 구축',
        'start': '2026-03-04',
        'end': '2026-03-04',
        'colorId': '9',
        'category': '구축'
    },
    {
        'summary': '🏗️ EKS 구축 - CMAS PRD',
        'description': 'CMAS PRD 환경 EKS 클러스터 구축',
        'start': '2026-03-04',
        'end': '2026-03-04',
        'colorId': '9',
        'category': '구축'
    },
    
    # EKS 업그레이드
    {
        'summary': '⬆️ EKS 업그레이드 - SMOA STG',
        'description': 'SMOA STG 환경 EKS 업그레이드 (평일 작업)',
        'start': '2026-02-23',
        'end': '2026-02-23',
        'colorId': '11',  # 빨간색
        'category': '업그레이드'
    },
    {
        'summary': '⬆️ EKS 업그레이드 - ITSM STG',
        'description': 'ITSM STG 환경 EKS 업그레이드 (평일 작업)',
        'start': '2026-02-26',
        'end': '2026-02-26',
        'colorId': '11',
        'category': '업그레이드'
    },
    {
        'summary': '⬆️ EKS 업그레이드 - AI-APP DEV',
        'description': 'AI-APP DEV 환경 EKS 업그레이드 (평일 작업)',
        'start': '2026-03-02',
        'end': '2026-03-02',
        'colorId': '11',
        'category': '업그레이드'
    },
    {
        'summary': '⬆️ EKS 업그레이드 - AI-APP STG',
        'description': 'AI-APP STG 환경 EKS 업그레이드 (평일 작업)',
        'start': '2026-03-05',
        'end': '2026-03-05',
        'colorId': '11',
        'category': '업그레이드'
    },
    {
        'summary': '⬆️ EKS 업그레이드 - SMOA PRD',
        'description': 'SMOA PRD 환경 EKS 업그레이드 (토요일 작업)',
        'start': '2026-03-07',
        'end': '2026-03-07',
        'colorId': '11',
        'category': '업그레이드'
    },
    {
        'summary': '⬆️ EKS 업그레이드 - ITSM PRD',
        'description': 'ITSM PRD 환경 EKS 업그레이드 (토요일 작업)',
        'start': '2026-03-07',
        'end': '2026-03-07',
        'colorId': '11',
        'category': '업그레이드'
    },
    {
        'summary': '⬆️ EKS 업그레이드 - AI-APP PRD',
        'description': 'AI-APP PRD 환경 EKS 업그레이드 (토요일 작업)',
        'start': '2026-03-14',
        'end': '2026-03-14',
        'colorId': '11',
        'category': '업그레이드'
    },
    
    # HELM 배포
    {
        'summary': '📦 EKS HELM 배포 - DEVPM',
        'description': 'DEVPM 환경 HELM 차트 배포',
        'start': '2026-01-27',
        'end': '2026-01-27',
        'colorId': '10',  # 초록색
        'category': 'HELM배포'
    },
    {
        'summary': '📦 EKS HELM 배포 - PRISM STG',
        'description': 'PRISM STG 환경 HELM 차트 배포',
        'start': '2026-01-27',
        'end': '2026-01-27',
        'colorId': '10',
        'category': 'HELM배포'
    },
    {
        'summary': '📦 EKS HELM 배포 - CMAS STG',
        'description': 'CMAS STG 환경 HELM 차트 배포',
        'start': '2026-02-17',
        'end': '2026-02-17',
        'colorId': '10',
        'category': 'HELM배포'
    },
    {
        'summary': '📦 EKS HELM 배포 - PRISM PRD',
        'description': 'PRISM PRD 환경 HELM 차트 배포',
        'start': '2026-03-10',
        'end': '2026-03-10',
        'colorId': '10',
        'category': 'HELM배포'
    },
    {
        'summary': '📦 EKS HELM 배포 - CMAS PRD',
        'description': 'CMAS PRD 환경 HELM 차트 배포',
        'start': '2026-03-10',
        'end': '2026-03-10',
        'colorId': '10',
        'category': 'HELM배포'
    },
]


def get_calendar_service():
    """Google Calendar API 서비스 객체 생성"""
    creds = None
    
    # token.pickle 파일에 저장된 인증 정보 확인
    if os.path.exists('token.pickle'):
        with open('token.pickle', 'rb') as token:
            creds = pickle.load(token)
    
    # 유효한 인증 정보가 없으면 로그인
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(
                'credentials.json', SCOPES)
            creds = flow.run_local_server(port=0)
        
        # 인증 정보 저장
        with open('token.pickle', 'wb') as token:
            pickle.dump(creds, token)
    
    return build('calendar', 'v3', credentials=creds)


def create_event(service, event_data):
    """Google Calendar에 이벤트 생성"""
    event = {
        'summary': event_data['summary'],
        'description': event_data['description'],
        'start': {
            'date': event_data['start'],
            'timeZone': 'Asia/Seoul',
        },
        'end': {
            'date': event_data['end'],
            'timeZone': 'Asia/Seoul',
        },
        'colorId': event_data['colorId'],
        'reminders': {
            'useDefault': False,
            'overrides': [
                {'method': 'email', 'minutes': 24 * 60},  # 1일 전
                {'method': 'popup', 'minutes': 60},  # 1시간 전
            ],
        },
    }
    
    created_event = service.events().insert(calendarId='primary', body=event).execute()
    return created_event


def main():
    """메인 함수"""
    print("🚀 EKS 프로젝트 일정을 Google Calendar에 등록합니다...\n")
    
    try:
        # Calendar API 서비스 생성
        service = get_calendar_service()
        print("✅ Google Calendar API 인증 완료\n")
        
        # 각 이벤트 생성
        success_count = 0
        for event_data in EVENTS:
            try:
                created_event = create_event(service, event_data)
                print(f"✅ {event_data['summary']}")
                print(f"   📅 {event_data['start']}")
                print(f"   🔗 {created_event.get('htmlLink')}\n")
                success_count += 1
            except Exception as e:
                print(f"❌ {event_data['summary']} 등록 실패: {str(e)}\n")
        
        print(f"\n🎉 완료! 총 {success_count}/{len(EVENTS)}개 이벤트가 등록되었습니다.")
        
        # 통계 출력
        categories = {}
        for event in EVENTS:
            cat = event['category']
            categories[cat] = categories.get(cat, 0) + 1
        
        print("\n📊 등록된 이벤트 통계:")
        for cat, count in categories.items():
            print(f"   {cat}: {count}건")
            
    except FileNotFoundError:
        print("❌ credentials.json 파일을 찾을 수 없습니다.")
        print("\n📝 설정 방법:")
        print("1. https://console.cloud.google.com/ 접속")
        print("2. 프로젝트 생성 또는 선택")
        print("3. 'API 및 서비스' > 'API 라이브러리'에서 'Google Calendar API' 활성화")
        print("4. 'API 및 서비스' > '사용자 인증 정보' > 'OAuth 2.0 클라이언트 ID' 생성")
        print("5. 애플리케이션 유형: '데스크톱 앱' 선택")
        print("6. credentials.json 다운로드 후 이 스크립트와 같은 폴더에 저장")
        print("7. 다시 실행: python eks-calendar-sync.py")
    except Exception as e:
        print(f"❌ 오류 발생: {str(e)}")


if __name__ == '__main__':
    main()
