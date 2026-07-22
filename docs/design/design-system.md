# Setflow 디자인 시스템 (2026) — 구현 확정본

> 브랜드 정체성(옐로우 `#FFCA10` + 잉크 `#241F20`)을 유지하며 2026 기준으로 현대화한 **구현용 스펙**.
> Flutter Material 3 기준. 이 문서의 수치를 `lib/theme/tokens.dart`로 코드화한다.

## 채택할 2026 트렌드 (→ 적용 방식)
1. **Material 3 Expressive** — 큰 타이포, 스프링 모션, 컨테이너 계층(surfaceContainer*), shape 강조 → 카드/버튼 라운드↑, 강조 색 적극.
2. **iOS 26 Liquid Glass 감성** — 반투명/깊이감 → 바텀시트·오버레이에 blur/elevation 계층.
3. **볼드 디스플레이 타이포** — 대시보드 핵심 숫자(볼륨/매출/진행률)를 크고 굵게.
4. **촉각 피드백** — 주요 액션에 `HapticFeedback.selectionClick/lightImpact`.
5. **상태 우선(state-first)** — 모든 리스트/폼에 로딩(스켈레톤)/빈/에러 상태 필수.
6. **모션** — 페이지/모달/마이크로 전환에 일관 duration+curve, 스프링 강조.
7. **접근성 기본값** — 대비 AA, 터치타깃 ≥48dp, 다크모드 동등.

## 1. 컬러 semantic 토큰

### 라이트
| 토큰 | hex | 용도 |
|---|---|---|
| primary | `#FFCA10` | 브랜드/주요 CTA |
| onPrimary | `#241F20` | primary 위 텍스트 |
| primaryContainer | `#FFF1BE` | tonal 버튼/강조 배경 |
| onPrimaryContainer | `#4A3B00` | 그 위 텍스트 |
| surface | `#FFFFFF` | 기본 배경 |
| surfaceContainerLow | `#F7F8FA` | 카드 배경(약) |
| surfaceContainer | `#F4F6F9` | 입력/칩 배경 |
| surfaceContainerHigh | `#EEF1F5` | 강조 컨테이너 |
| onSurface | `#241F20` | 본문 |
| onSurfaceVariant | `#6B7280` | 보조 텍스트 |
| disabled | `#9CA3AF` | 비활성 |
| outline | `#E3E5E5` | 구분선/보더 |
| outlineVariant | `#EEF0F2` | 약한 보더 |

### 다크
| 토큰 | hex |
|---|---|
| primary | `#FFD53D` (다크에서 살짝 밝게) |
| onPrimary | `#241F20` |
| primaryContainer | `#4A3B00` |
| onPrimaryContainer | `#FFE9A0` |
| surface | `#181719` |
| surfaceContainerLow | `#1E1D20` |
| surfaceContainer | `#232227` |
| surfaceContainerHigh | `#2A2930` |
| onSurface | `#F7F7F7` |
| onSurfaceVariant | `#A1A1AA` |
| disabled | `#6B7280` |
| outline | `#343236` |
| outlineVariant | `#2A282C` |

### 상태색 (라/다 공통, 다크는 컨테이너만 조정)
| 토큰 | hex |
|---|---|
| success | `#22C55E` |
| warning | `#F59E0B` |
| error | `#EF4444` |
| info | `#3B82F6` |

### 액센트(역할/카테고리)
| 이름 | hex | 용도 |
|---|---|---|
| teal | `#10CEBD` | 회원/루틴 |
| blue | `#3B82F6` | 트레이너 |
| purple | `#8B5CF6` | 헬스장 |
| orange | `#FFB20C` | 강조 |

## 2. 타이포 스케일 (system sans, 기존 볼드 감성 유지)
| 토큰 | size(pt) | weight | line-height |
|---|---|---|---|
| displayLarge | 32 | 900 | 1.15 |
| displayMedium | 28 | 800 | 1.2 |
| headlineLarge | 24 | 800 | 1.25 |
| headlineMedium | 20 | 800 | 1.3 |
| titleLarge | 18 | 700 | 1.3 |
| titleMedium | 16 | 700 | 1.4 |
| bodyLarge | 15 | 500 | 1.5 |
| bodyMedium | 14 | 500 | 1.5 |
| labelLarge | 14 | 700 | 1.2 |
| labelMedium | 12 | 600 | 1.3 |
| caption | 11 | 500 | 1.3 |

## 3. 스페이싱 스케일 (4pt 기반)
`space = [2, 4, 8, 12, 16, 20, 24, 32, 40, 48]`
- 화면 좌우 패딩 기본 **24**, 카드 내부 **16~18**, 요소 간격 **12~16**, 섹션 간격 **24~32**.

## 4. 라운드 스케일
| 이름 | 값 |
|---|---|
| xs | 8 |
| sm | 12 |
| md | 16 (입력/버튼 기본) |
| lg | 20 (카드 기본) |
| xl | 28 (바텀시트/모달) |
| full | 999 (칩/아바타/토글) |

## 5. 엘리베이션/섀도우
| level | 스펙 |
|---|---|
| 1 (카드) | `BoxShadow(color: 0x14000000, blurRadius: 12, offset: (0,4))` |
| 2 (팝업/버튼호버) | `BoxShadow(color: 0x1A000000, blurRadius: 24, offset: (0,8))` |
| 3 (모달/시트) | `BoxShadow(color: 0x24000000, blurRadius: 40, offset: (0,16))` |
> 다크모드는 섀도우 약화 + `surfaceContainer` 밝기로 계층 표현.

## 6. 모션
| 종류 | duration | curve |
|---|---|---|
| 마이크로(탭/토글/스케일) | 150ms | easeOut |
| 표준(전환/스위처) | 260ms | easeOutCubic |
| 페이지 | 320ms | easeOutCubic |
| 강조(스프링) | — | `Curves.easeOutBack` 또는 spring |
- 버튼 press: scale `0.98`, 150ms. 리스트 진입: stagger fade+slide(y 8→0).

## 7. 컴포넌트 스펙 (숫자 확정)
| 컴포넌트 | 스펙 |
|---|---|
| **PrimaryButton** | height 52, radius md(16), padding h20, label labelLarge/800, press scale .98, disabled opacity .4 |
| **TonalButton** | bg primaryContainer, text onPrimaryContainer, 나머지 동일 |
| **TextButton** | text primary, height 44 |
| **Card(SetflowCard)** | radius lg(20), padding 16~18, elevation1, light엔 outlineVariant 1px |
| **Input** | radius md(16), filled surfaceContainer, focus 2px primary, contentPad h16 v15, error 시 error보더+하단 메시지 |
| **Chip/FilterChip** | height 36, radius full, 선택 시 primaryContainer/onPrimaryContainer |
| **BottomNav** | height 64, 선택 인디케이터 pill(primaryContainer), 라벨 alwaysShow |
| **ListTile** | minHeight 56, 탭 하이라이트 radius md |
| **Badge** | radius full, 상태색 배경, caption/700 |
| **SnackBar** | floating, radius sm(14), 성공/에러 시 상태색 리딩아이콘 |
| **Skeleton** | surfaceContainerHigh, shimmer 1200ms, radius md |
| **EmptyState** | 아이콘 56 + 제목 titleMedium + 설명 bodyMedium + (선택)CTA |

## 8. 상태 컴포넌트 (신규 필수)
프로덕션 품질을 위해 아래 공용 위젯을 `widgets/common.dart`(또는 `widgets/states.dart`)에 추가:
- `LoadingState` (스켈레톤/스피너)
- `EmptyState` (아이콘+메시지+CTA)
- `ErrorState` (재시도 버튼)
- `AppSnackbar.success/error/info(context, msg)` 헬퍼
- `AppButton`(primary/tonal/text variant 통합), `AppTextField`(검증/에러 내장)

## 9. 구현 순서 (Phase B)
1. `lib/theme/tokens.dart` — 위 토큰을 `SetflowColors`(하위호환 유지) + 신규 semantic 게터로.
2. `theme.dart` — ColorScheme/TextTheme/컴포넌트 테마를 위 스펙으로 재구성 (기존 클래스명 유지).
3. `widgets/common.dart` — 컴포넌트 스펙 반영 + 상태 위젯 추가.
4. `flutter analyze` + `flutter build web` 게이트.

> **하위호환 원칙**: 기존 `SetflowColors.primary/teal/...`, `SetflowCard`, `PrimaryButton` 이름/시그니처는 유지하고 **값/스타일만 업그레이드**해서, 전 화면 일괄 깨짐 없이 점진 적용.

_확정일: 2026-07-22 · 근거: React `index.css` 브랜드 토큰 + 2026 트렌드(M3 Expressive, iOS 26)_
