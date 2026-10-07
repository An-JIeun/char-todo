# CharTodo 🦁

뉴트로 감성 macOS 할일 앱. 오늘·주간·월간 할일, 아이젠하워 매트릭스, 세부 테스크, 태그 분류, 업무일지 + TIL,
macOS 캘린더 연동, 그리고 화면 위에 떠 있는 캐릭터 질문봇(LLM 브리핑)을 담았습니다.

---

## 1. 실행 방법

### 준비물

| 항목 | 확인 / 설치 |
| --- | --- |
| macOS 14 (Sonoma) 이상 | 메뉴 → 이 Mac에 관하여 |
| Swift 빌드 도구 (Xcode 또는 Command Line Tools) | 터미널에서 `swift --version` 이 나오면 OK. 없으면 `xcode-select --install` |

Xcode 앱은 없어도 됩니다. Command Line Tools만으로 빌드됩니다.

### 처음 실행

```bash
cd ~/Documents/GitHub/char-todo   # 저장소 폴더로 이동
./scripts/build-app.sh            # build/CharTodo.app 생성 (처음엔 1~2분)
open build/CharTodo.app           # 실행
```

실행하면 메인 창, 화면 오른쪽 아래에 떠 있는 캐릭터, 메뉴바의 ✓ 아이콘이 나타납니다.

### 응용 프로그램 폴더에 설치 (선택)

```bash
cp -R build/CharTodo.app /Applications/
```

이후에는 Spotlight(⌘Space)에서 `CharTodo` 로 실행할 수 있습니다.

**로그인할 때 자동 실행**: 시스템 설정 → 일반 → 로그인 항목 → `+` → CharTodo 선택.

### 코드를 고친 뒤 다시 실행

```bash
osascript -e 'quit app "CharTodo"'   # 실행 중인 앱 종료 (데이터는 자동 저장됨)
./scripts/build-app.sh debug         # debug 빌드가 더 빠름
open build/CharTodo.app
```

`/Applications` 에 설치해 두었다면 다시 `cp -R build/CharTodo.app /Applications/` 로 덮어쓰세요.

> 창을 닫아도 떠 있는 캐릭터 때문에 앱은 계속 실행됩니다. 완전히 끄려면 ⌘Q 또는 메뉴바 ✓ 아이콘 → ⏻ 버튼.

### 처음 실행할 때 나올 수 있는 창

| 창 | 설명 |
| --- | --- |
| 캘린더 접근 허용 | 설정 → 캘린더 → **권한 요청** 을 누를 때 나옵니다. 거부했다면 시스템 설정 → 개인정보 보호 및 보안 → 캘린더에서 CharTodo를 켜세요. |
| 키체인 접근 허용 | API 키를 저장/읽을 때 나옵니다. **항상 허용**을 누르세요. 앱을 다시 빌드하면 서명이 바뀌어 한 번 더 물어볼 수 있습니다. |
| "확인되지 않은 개발자" | 직접 빌드한 앱은 보통 바로 열립니다. 다른 Mac으로 복사한 경우 앱을 우클릭 → **열기**, 또는 `xattr -dr com.apple.quarantine /Applications/CharTodo.app` |

---

## 2. AI 비서 연결

설정(⌘7) → **AI 비서** 에서 공급자를 고르고 **연결 테스트**를 눌러 확인하세요.

### Ollama (내 Mac, 무료·오프라인)

```bash
brew install ollama        # 또는 ollama.com 에서 앱 설치
ollama serve               # 앱으로 설치했다면 생략
ollama pull qwen2.5:7b     # 한국어는 qwen·gemma 계열 추천
```

앱: 서버 주소 `http://localhost:11434` → **모델 불러오기** → 모델 선택.

### Ollama (홈서버)

서버에서 외부 접속을 허용해 실행합니다.

```bash
OLLAMA_HOST=0.0.0.0 ollama serve
```

systemd로 돌린다면 서비스에 `Environment="OLLAMA_HOST=0.0.0.0"` 를 넣고 재시작. 방화벽/공유기에서 11434 포트를 열고,
앱에는 `http://<홈서버 주소>:11434` 를 입력합니다. 큰 모델은 첫 응답이 느릴 수 있어요.

### LM Studio / OpenAI 호환 API

**OpenAI 호환** 선택 → Base URL 프리셋(LM Studio `http://localhost:1234/v1`, OpenAI, OpenRouter, Gemini) → 필요하면 API 키 → 모델.

### Claude API (Anthropic 키)

console.anthropic.com 에서 키 발급 → **Claude API** 선택 → 키 입력 후 **키체인에 저장** → 모델(Opus 5.5 / Sonnet 5.5 / Haiku 4.5)과 생각 깊이 선택.

### Claude Code CLI (Claude 구독 로그인 사용, API 키 불필요)

```bash
curl -fsSL https://claude.ai/install.sh | bash   # 또는 npm install -g @anthropic-ai/claude-code
claude                                           # 한 번 실행해서 로그인
```

앱이 `~/.local/bin/claude` 등을 자동으로 찾습니다. 못 찾으면 설정에서 경로를 직접 지정하세요.
`Failed to authenticate` 가 나오면 터미널에서 `claude auth login` 으로 다시 로그인하세요.

---

## 3. 기능

| 화면 (단축키) | 내용 |
| --- | --- |
| 오늘 (⌘1) | 뜯는 달력 헤더, 오늘 할일·밀린 할일, 캘린더 일정 타임라인, 주간/월간 목표, 브리핑 버튼 |
| 주간 (⌘2) | 7일 칸 플래너(드래그로 날짜 이동), 주간 목표 |
| 월간 (⌘3) | 월 달력(할일·일정·일지 표시), 월간 목표, 날짜 상세 |
| 매트릭스 (⌘4) | 아이젠하워 4분면, 드래그로 분류, 미분류 트레이, 태그 필터, AI 우선순위 |
| 태그 (⌘5) | 태그별 모아보기(밀린·오늘·예정·목표·완료), 이름 변경/합치기, 색 지정, 삭제 |
| 업무일지·TIL (⌘6) | 오늘 한 일 / 이슈·회고 / 내일 할 일 / TIL 카드, 완료 할일 가져오기, AI 초안, 마크다운 내보내기 |
| 설정 (⌘7) | 테마 7종, AI 공급자, 말투, 캐릭터 리깅, 캘린더, 일반 |

기타 단축키: ⌘⇧B 오늘 브리핑 · ⌘J 질문봇 열기/닫기 · ⌘⇧K 캐릭터 보이기/숨기기

### 빠른 입력 문법

`보고서 작성 !1 @내일 ~14:30 #업무 > 자료조사, 초안, 검토`

| 문법 | 의미 |
| --- | --- |
| `!1` ~ `!4` | 아이젠하워 사분면 (Q1 지금 하기 … Q4 버리기) |
| `@오늘` `@내일` `@모레` `@금` `@10/12` | 날짜 |
| `~14:30` `~오후3시` | 시각 |
| `#업무` `#공부` | 태그 (여러 개 가능) |
| `#주간` `#월간` | 주간·월간 목표로 등록 |
| `제목 > 세부1, 세부2` | 세부 테스크 한 번에 |

### 태그

- 빠른 입력의 `#태그`, 할일 편집 창의 태그 입력(기존 태그 추천), 우클릭 → 태그 메뉴로 붙입니다.
- 할일의 태그 칩을 누르면 태그 화면에서 그 태그만 모아 봅니다.
- 태그 화면 목록으로 할일을 끌어다 놓으면 그 태그가 붙습니다.
- 태그 화면에서 선택한 태그로 할일을 추가하면 태그가 자동으로 붙습니다.

### AI 브리핑 / 질문봇

- 오늘 할일·밀린 일·캘린더 일정·어제 업무일지를 보고 브리핑합니다.
- 답변 속 `[[ADD|제목|날짜|범위|Q1]]` 태그는 "할일 추가" 버튼으로 바뀝니다.
- 세부 테스크 AI로 쪼개기, 업무일지 AI 초안.

### 캐릭터

- 이미지 넣기 → (선택) Vision으로 배경 지우기 → 핸들로 얼굴·팔다리 위치 지정
- 얼굴: 직접 그리기 / 이미지 얼굴 위에 깜빡임·말하는 입만 덧그리기
- 팔다리: 고무호스 스타일 또는 손그림(채움+외곽선), 손·발 모양, 몸 앞/뒤
- 상태별 모션: 대기 · 듣는 중 · 생각 중 · 말하는 중 · 신남(완료 축하) · 졸림
- 클릭: 질문봇 / 더블클릭: 메인 창 / 드래그: 이동 / 우클릭: 메뉴

### 말투

기본 성격, 캐릭터 설정, 문장 끝 어미, 말버릇(빈도), 상황별 표현(인사·브리핑·완료·올클리어·밀린 일·응원·마무리·생각 중), 피할 표현.
상황별 표현은 말풍선에 그대로 쓰이고 AI 답변에도 반영됩니다. `{n}` = 개수, `{이름}` = 캐릭터 이름.

---

## 4. 문제 해결

| 증상 | 해결 |
| --- | --- |
| 캐릭터가 안 보임 | ⌘⇧K 또는 메뉴바 ✓ → 👁 버튼, 설정 → 일반 → 떠 있는 캐릭터 |
| 메인 창을 닫았는데 다시 열고 싶음 | Dock 아이콘 클릭, 캐릭터 더블클릭, 메뉴바 ✓ → 메인 창 |
| 연결 테스트가 오래 걸림 | 로컬/홈서버 모델의 첫 로딩이 느린 경우가 많습니다. 더 작은 모델을 쓰거나 Claude로 바꿔 보세요. |
| `Failed to authenticate` (Claude Code) | 터미널에서 `claude auth login` |
| 홈서버 연결 실패 | 오류 메시지의 안내대로 `OLLAMA_HOST=0.0.0.0`, 포트, 주소를 확인 |
| 캘린더 일정이 안 보임 | 설정 → 캘린더 → 연동 켜기 + 권한 허용 + 표시할 캘린더 체크 |

---

## 5. 데이터 · 백업 · 삭제

- 저장 위치: `~/Library/Application Support/CharTodo/` (`data.json` 할일·일지, `settings.json` 설정, `character/` 캐릭터 이미지)
- API 키: macOS 키체인 (`com.lempickaaa.CharTodo.llm`)
- 백업: 설정 → 일반 → **백업 내보내기**, 또는 위 폴더를 통째로 복사

완전히 지우기:

```bash
rm -rf /Applications/CharTodo.app ~/Library/Application\ Support/CharTodo
defaults delete com.lempickaaa.CharTodo
```

키체인의 API 키는 키체인 접근 앱에서 `com.lempickaaa.CharTodo.llm` 을 검색해 지우세요.

---

## 6. 개발

```bash
swift build                    # 컴파일만
./scripts/test.sh              # 테스트 (Command Line Tools에서도 동작)
./scripts/build-app.sh debug   # 빠른 앱 번들
```

- `swift run` 으로 직접 실행하면 앱 번들(Info.plist)이 없어 캘린더 권한 등이 동작하지 않습니다. `build-app.sh` 를 쓰세요.
- `CHARTODO_DATA_DIR=<폴더>` : 다른 데이터 폴더로 실행 (실데이터 보호용)
- `CHARTODO_SNAPSHOT_DIR=<폴더>` : 각 화면을 PNG로 저장 후 계속 실행 (UI 확인용)

```bash
CHARTODO_DATA_DIR=/tmp/ct-data CHARTODO_SNAPSHOT_DIR=/tmp/ct-shots build/CharTodo.app/Contents/MacOS/CharTodo
```

구조: `Sources/CharTodo/` — `Models`(할일·일지·설정·캐릭터) · `Store`(JSON 저장) · `Services`(캘린더·키체인·빠른 입력·배경 제거) ·
`LLM`(공급자별 스트리밍 클라이언트·프롬프트·대화) · `Theme`(테마·레트로 컴포넌트) · `Views`(화면) · `Floating`(떠 있는 캐릭터·질문봇)
