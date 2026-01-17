# dialysis_app

투석 기록/체중/혈압을 Google Sheets에 월별로 저장하고, 모바일 건강데이터와 연동하는 Flutter 앱입니다.

## 필수 설정

### OAuth 2.0 클라이언트
- Google Cloud Console에서 OAuth 2.0 클라이언트 ID/Secret 생성
- Replit에서 제공하는 Redirect URL을 승인된 리디렉션 URI에 등록

### Secrets 저장
- `CLIENT_ID`와 `CLIENT_SECRET`을 FlutterFlow Secrets 도구에 저장

### 건강 데이터 권한
- Android: `android/app/src/main/AndroidManifest.xml`에 Health Connect 권한 추가
- iOS: `ios/Runner/Info.plist`에 `NSHealthShareUsageDescription` 및 `NSHealthUpdateUsageDescription` 추가

### Google API 활성화
- Google Sheets API, Google Drive API를 프로젝트에서 활성화

### Android 설정
- 패키지명: `com.dollee.dialysisApp`
- `android/app/google-services.json` 추가
- SHA-1 등록 필요 (Google Cloud Console > Android 앱)

### iOS 설정
- `ios/Runner/GoogleService-Info.plist` 추가
- `ios/Flutter/Debug.xcconfig`과 `ios/Flutter/Release.xcconfig`에 아래 값 설정
  - `GID_CLIENT_ID`
  - `REVERSED_CLIENT_ID`
- iOS Deployment Target: `14.0` 이상

## 실행

```
flutter pub get
flutter run -d <device_id>
```

## 주요 동작
- 로그인 후 월별 Google Sheets 파일 생성
- 파일은 Drive의 `투석결과App` 폴더에 자동 저장
- 데이터 공유는 폴더 공유 방식 (한 번만 공유)
- 체중/혈압 입력 시 건강데이터 읽기/쓰기 지원
- 메인 화면에서 맥박/오늘 걸음 수 표시

## 문제 해결
- Sheets API 403: Google Sheets API 활성화 후 재시도 (전파 지연 2~5분 가능)
- iOS 로그인 크래시: `GIDClientID`가 Info.plist에 설정되어 있는지 확인
