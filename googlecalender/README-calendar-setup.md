# 📅 EKS 프로젝트 일정 Google Calendar 자동 등록

## 🎯 개요
EKS 구축/업그레이드/배포 일정을 Google Calendar에 자동으로 등록하는 Python 스크립트입니다.

## 📋 사전 준비

### 1. Python 패키지 설치
```bash
pip install google-auth-oauthlib google-auth-httplib2 google-api-python-client
```

### 2. Google Cloud Console 설정

#### Step 1: 프로젝트 생성
1. [Google Cloud Console](https://console.cloud.google.com/) 접속
2. 새 프로젝트 생성 또는 기존 프로젝트 선택

#### Step 2: Calendar API 활성화
1. 좌측 메뉴 > **API 및 서비스** > **라이브러리**
2. "Google Calendar API" 검색
3. **사용 설정** 클릭

#### Step 3: OAuth 2.0 인증 정보 생성
1. 좌측 메뉴 > **API 및 서비스** > **사용자 인증 정보**
2. 상단 **+ 사용자 인증 정보 만들기** > **OAuth 클라이언트 ID**
3. 애플리케이션 유형: **데스크톱 앱** 선택
4. 이름 입력 (예: "EKS Calendar Sync")
5. **만들기** 클릭
6. **JSON 다운로드** 클릭
7. 다운로드한 파일을 `credentials.json`으로 이름 변경
8. 이 스크립트와 같은 폴더에 저장

## 🚀 사용 방법

### 기본 실행
```bash
python eks-calendar-sync.py
```

### 첫 실행 시
1. 브라우저가 자동으로 열립니다
2. Google 계정으로 로그인
3. 권한 요청 승인
4. "인증이 완료되었습니다" 메시지 확인
5. 스크립트가 자동으로 이벤트 등록 시작

### 이후 실행
- `token.pickle` 파일이 생성되어 자동 로그인됩니다
- 재인증이 필요하면 `token.pickle` 파일을 삭제하고 다시 실행

## 📊 등록되는 이벤트

### 🏗️ EKS 구축 (파란색)
- PRISM STG (1월 27일)
- CMAS STG (2월 17일)
- PRISM PRD (3월 4일)
- CMAS PRD (3월 4일)

### ⬆️ EKS 업그레이드 (빨간색)
- SMOA STG (2월 23일 - 평일)
- ITSM STG (2월 26일 - 평일)
- AI-APP DEV (3월 2일 - 평일)
- AI-APP STG (3월 5일 - 평일)
- SMOA PRD (3월 7일 - 토요일)
- ITSM PRD (3월 7일 - 토요일)
- AI-APP PRD (3월 14일 - 토요일)

### 📦 HELM 배포 (초록색)
- DEVPM (1월 27일)
- PRISM STG (1월 27일)
- CMAS STG (2월 17일)
- PRISM PRD (3월 10일)
- CMAS PRD (3월 10일)

## 🔔 알림 설정
각 이벤트에 자동으로 알림이 설정됩니다:
- 📧 이메일: 1일 전
- 🔔 팝업: 1시간 전

## 🎨 색상 코드
- 🔵 파란색 (9): EKS 구축
- 🔴 빨간색 (11): EKS 업그레이드
- 🟢 초록색 (10): HELM 배포

## 🔧 커스터마이징

### 날짜 수정
`eks-calendar-sync.py` 파일의 `EVENTS` 리스트에서 날짜 수정:
```python
{
    'summary': '🏗️ EKS 구축 - PRISM STG',
    'start': '2025-01-27',  # 여기 수정
    'end': '2025-01-27',    # 여기 수정
    ...
}
```

### 알림 시간 변경
`create_event` 함수의 `reminders` 부분 수정:
```python
'overrides': [
    {'method': 'email', 'minutes': 24 * 60},  # 1일 전 이메일
    {'method': 'popup', 'minutes': 60},       # 1시간 전 팝업
],
```

### 이벤트 추가
`EVENTS` 리스트에 새 항목 추가:
```python
{
    'summary': '🔧 새 작업',
    'description': '작업 설명',
    'start': '2025-04-01',
    'end': '2025-04-01',
    'colorId': '9',
    'category': '카테고리'
}
```

## ⚠️ 문제 해결

### "credentials.json을 찾을 수 없습니다"
- Google Cloud Console에서 OAuth 2.0 클라이언트 ID를 생성했는지 확인
- JSON 파일을 다운로드하고 `credentials.json`으로 이름 변경
- 스크립트와 같은 폴더에 있는지 확인

### "API가 활성화되지 않았습니다"
- Google Cloud Console에서 Calendar API를 활성화했는지 확인
- 프로젝트가 올바르게 선택되었는지 확인

### "권한이 거부되었습니다"
- OAuth 동의 화면에서 모든 권한을 승인했는지 확인
- `token.pickle` 파일을 삭제하고 다시 인증

### 중복 이벤트 방지
스크립트를 여러 번 실행하면 이벤트가 중복 생성됩니다. 중복을 방지하려면:
1. Google Calendar에서 기존 이벤트 삭제
2. 스크립트 재실행

또는 스크립트를 수정하여 중복 체크 로직 추가 가능합니다.

## 📝 파일 구조
```
.
├── eks-calendar-sync.py      # 메인 스크립트
├── credentials.json           # Google OAuth 인증 정보 (직접 생성)
├── token.pickle              # 자동 생성되는 인증 토큰
└── README-calendar-setup.md  # 이 파일
```

## 🔒 보안 주의사항
- `credentials.json`과 `token.pickle`은 민감한 정보입니다
- Git에 커밋하지 마세요 (.gitignore에 추가 권장)
- 팀원과 공유하지 마세요 (각자 생성해야 함)

## 💡 추가 기능 아이디어
- [ ] 중복 이벤트 자동 체크 및 업데이트
- [ ] CSV/Excel 파일에서 일정 읽어오기
- [ ] 팀 캘린더에 자동 공유
- [ ] Slack 알림 연동
- [ ] 작업 완료 시 자동 체크
