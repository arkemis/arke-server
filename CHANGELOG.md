# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.2] - 2025-10-02

### Changed
- Handle direct html in mailer by @vittorio-reinaudo in [#88](https://github.com/arkemishub/arke-server/pull/88)

## [0.4.1] - 2025-08-13

### Added
- Add support for load_files in topology get by @ilyichv in [#87](https://github.com/arkemishub/arke-server/pull/87)

## [0.4.0] - 2025-06-03

### Added
- Add nested filters and order by @ilyichv in [#86](https://github.com/arkemishub/arke-server/pull/86)

## [0.3.18] - 2025-04-10

### Changed
- Options that are passed to onesignal api are now fully customizable in [#84](https://github.com/arkemishub/arke-server/pull/84)

### Fixed
- Gh action by @ErikFerrari in [#85](https://github.com/arkemishub/arke-server/pull/85)

### New Contributors
* @ made their first contribution in [#84](https://github.com/arkemishub/arke-server/pull/84)

## [0.3.17] - 2025-02-14

### Changed
- Implemented new permission check for impersonate, added auth pipeline for impersonate by @Robbi-aka-Rob in [#83](https://github.com/arkemishub/arke-server/pull/83)

### Fixed
- Arke min deps by @ErikFerrari

### New Contributors
* @Robbi-aka-Rob made their first contribution in [#83](https://github.com/arkemishub/arke-server/pull/83)

## [0.3.16] - 2025-01-14

### Changed
- Global catcher for raised error by @vittorio-reinaudo in [#64](https://github.com/arkemishub/arke-server/pull/64)

### Fixed
- Onesignal parse member id by @ErikFerrari in [#80](https://github.com/arkemishub/arke-server/pull/80)
- Runtime data get_unit plug by @ErikFerrari in [#81](https://github.com/arkemishub/arke-server/pull/81)

## [0.3.15] - 2024-12-16

### Added
- Add attachments to email by @vittorio-reinaudo in [#79](https://github.com/arkemishub/arke-server/pull/79)

## [0.3.14] - 2024-11-19

### Added
- Add cc to email base mailer struct by @vittorio-reinaudo in [#76](https://github.com/arkemishub/arke-server/pull/76)

## [0.3.13] - 2024-10-24

### Added
- Add runtime_data conn in unit update by @vittorio-reinaudo in [#75](https://github.com/arkemishub/arke-server/pull/75)

### Changed
- Export_data endpoint by @vittorio-reinaudo in [#74](https://github.com/arkemishub/arke-server/pull/74)

## [0.3.12] - 2024-10-01

### Fixed
- Refresh token by @ErikFerrari

## [0.3.11] - 2024-09-25

### Changed
- Downcase email value in signin signup with oauth by @vittorio-reinaudo in [#71](https://github.com/arkemishub/arke-server/pull/71)

## [0.3.10] - 2024-09-03

### Added
- Add signin via arke temporary_token by @vittorio-reinaudo in [#68](https://github.com/arkemishub/arke-server/pull/68)

## [0.3.9] - 2024-08-06

### Added
- Add param last_access_time on signup by @vittorio-reinaudo in [#67](https://github.com/arkemishub/arke-server/pull/67)

## [0.3.8] - 2024-08-02

### Added
- Add microsoft provider for oauth by @vittorio-reinaudo in [#66](https://github.com/arkemishub/arke-server/pull/66)

## [0.3.7] - 2024-07-22

### Fixed
- Hide phone number empty string by @ErikFerrari in [#65](https://github.com/arkemishub/arke-server/pull/65)
- Hide phone number by @ErikFerrari

## [0.3.6] - 2024-07-09

### Fixed
- Oauth login update access time by @ErikFerrari in [#62](https://github.com/arkemishub/arke-server/pull/62)

## [0.3.5] - 2024-07-05

### Added
- Add otp management via sms by @vittorio-reinaudo in [#61](https://github.com/arkemishub/arke-server/pull/61)

### New Contributors
* @vittorio-reinaudo made their first contribution in [#61](https://github.com/arkemishub/arke-server/pull/61)

## [0.3.4] - 2024-06-26

### Changed
- Align dev by @ErikFerrari in [#60](https://github.com/arkemishub/arke-server/pull/60)

## [0.3.3] - 2024-06-05

### Fixed
- Update member login time by @ErikFerrari in [#59](https://github.com/arkemishub/arke-server/pull/59)

## [0.3.2] - 2024-06-04

### Changed
- Health endpoint by @ErikFerrari

### Fixed
- Oauth signin and signup email by @ErikFerrari in [#58](https://github.com/arkemishub/arke-server/pull/58)

## [0.3.1] - 2024-05-21

### Fixed
- Change pwd permission plug by @ErikFerrari in [#56](https://github.com/arkemishub/arke-server/pull/56)

## [0.3.0] - 2024-04-23

### Changed
- Set version to v0.3.0 by @ErikFerrari
- Registry file by @ErikFerrari in [#46](https://github.com/arkemishub/arke-server/pull/46)

## [0.1.39] - 2024-04-02

### Changed
- Handeld first_access_time and last_access_time on signin GET method by @dorianmercatante

## [0.1.38] - 2024-04-02

### Added
- Added auth_token api for member by @dorianmercatante

### Changed
- Handeld first_access_time and last_access_time on signin api by @dorianmercatante

## [0.1.37] - 2024-02-21

### Changed
- File response in arke functions by @dorianmercatante

## [0.1.36] - 2024-02-16

### Changed
- Handled child_only_permission by @dorianmercatante in [#50](https://github.com/arkemishub/arke-server/pull/50)

## [0.1.35] - 2024-02-07

### Fixed
- Parenthesis query by @ErikFerrari in [#48](https://github.com/arkemishub/arke-server/pull/48)

## [0.1.34] - 2024-02-01

### Added
- Add update link route and method by @ilyichv in [#47](https://github.com/arkemishub/arke-server/pull/47)

### Changed
- Set version to v0.1.34 by @ilyichv

## [0.1.33] - 2024-01-30

### Changed
- Better error handling in query_filter by @ErikFerrari in [#45](https://github.com/arkemishub/arke-server/pull/45)

## [0.1.32] - 2024-01-17

### Changed
- Set version to v0.1.32 by @manolo-battista
- Review email for tester OTP signin by @manolo-battista in [#43](https://github.com/arkemishub/arke-server/pull/43)

### Fixed
- Typo default on AUTH_MODE by @manolo-battista in [#41](https://github.com/arkemishub/arke-server/pull/41)

## [0.1.31] - 2024-01-11

### Fixed
- Onesignal env and local variables by @manolo-battista

### New Contributors
* @manolo-battista made their first contribution

## [0.1.30] - 2024-01-05

### Changed
- Handled coordinates filter in unit get all by @dorianmercatante

## [0.1.29] - 2024-01-05

### Added
- Added onesignal utils by @dorianmercatante

## [0.1.28] - 2023-12-22

### Changed
- Enable email send for otp apis by @dorianmercatante

## [0.1.27] - 2023-12-22

### Added
- Add runtime data to unit controller update by @ilyichv in [#39](https://github.com/arkemishub/arke-server/pull/39)

### Changed
- Set version to v0.1.27 by @ilyichv

## [0.1.26] - 2023-12-18

### Changed
- Return essential data in signin with otp by @dorianmercatante

## [0.1.25] - 2023-12-14

### Changed
- Handled signup member by @dorianmercatante

## [0.1.24] - 2023-12-12

### Fixed
- Responses in arke function api by @dorianmercatante

## [0.1.23] - 2023-12-11

### Changed
- Handled post arke call func by @dorianmercatante

## [0.1.22] - 2023-12-05

### Added
- Add status to arke_controller call_function by @ilyichv in [#38](https://github.com/arkemishub/arke-server/pull/38)

### Changed
- Set version to v0.1.22 by @ilyichv

## [0.1.21] - 2023-12-04

### Changed
- Set version to v0.1.21 by @ilyichv
- Update associated parameter by @ilyichv in [#37](https://github.com/arkemishub/arke-server/pull/37)

## [0.1.20] - 2023-11-21

### Fixed
- Fixed negate filters by @dorianmercatante

## [0.1.19] - 2023-11-17

### Changed
- Handled otp for reset password by @dorianmercatante

## [0.1.18] - 2023-11-15

### Changed
- Handled otp auth method by @dorianmercatante

## [0.1.17] - 2023-10-26

### Changed
- Handle load_files opts by @dorianmercatante

## [0.1.16] - 2023-10-17

### Changed
- Handled unit function api and removed references ro old managers by @dorianmercatante

## [0.1.15] - 2023-10-05

### Changed
- Set version to v0.1.15 by @dorianmercatante
- Passed conn as runtime_data in create and struct api by @dorianmercatante

## [0.1.14] - 2023-08-31

### Changed
- Set version to v0.1.14 by @ErikFerrari

### Fixed
- Reset password token creation by @ErikFerrari in [#35](https://github.com/arkemishub/arke-server/pull/35)

## [0.1.12] - 2023-08-30

### Changed
- Set version to v0.1.12 by @ErikFerrari
- Email manager by @ErikFerrari in [#30](https://github.com/arkemishub/arke-server/pull/30)

## [0.1.11] - 2023-07-12

### Changed
- Set version to v0.1.11 by @ErikFerrari
- Handled load_values as query parameter by @dorianmercatante in [#26](https://github.com/arkemishub/arke-server/pull/26)

## [0.1.10] - 2023-07-10

### Added
- Add isnull filter operator by @ErikFerrari in [#23](https://github.com/arkemishub/arke-server/pull/23)

### Changed
- Set version to v0.1.10 by @dorianmercatante

### Fixed
- Retrieved group parameters in group struct api by @dorianmercatante in [#24](https://github.com/arkemishub/arke-server/pull/24)

## [0.1.9] - 2023-06-29

### Added
- Add/delete node pass strings to LinkManager by @ilyichv in [#21](https://github.com/arkemishub/arke-server/pull/21)

### Changed
- Set version to v0.1.9 by @ilyichv
- Enable GH action tests by @ilyichv in [#22](https://github.com/arkemishub/arke-server/pull/22)

### Fixed
- Init by @ErikFerrari in [#18](https://github.com/arkemishub/arke-server/pull/18)

## [0.1.8] - 2023-06-16

### Changed
- Set version to v0.1.8 by @ErikFerrari

### Fixed
- Single in param by @ErikFerrari in [#17](https://github.com/arkemishub/arke-server/pull/17)

## [0.1.7] - 2023-06-16

### Changed
- Set version to v0.1.7 by @ErikFerrari

### Fixed
- Build in filters from query params by @ErikFerrari in [#16](https://github.com/arkemishub/arke-server/pull/16)

## [0.1.6] - 2023-06-15

### Changed
- Set version to v0.1.6 by @ErikFerrari

### Fixed
- Return 400 if no operator or logic has been found by @ErikFerrari in [#14](https://github.com/arkemishub/arke-server/pull/14)

## [0.1.5] - 2023-06-13

### Added
- Add change_password auth endpoint by @ilyichv in [#15](https://github.com/arkemishub/arke-server/pull/15)

### Changed
- Set version to v0.1.5 by @ilyichv

### Fixed
- ParameterController now use the ParameterController module by @ErikFerrari in [#12](https://github.com/arkemishub/arke-server/pull/12)

## [0.1.4] - 2023-05-31

### Changed
- Set version to 0.1.4 by @ilyichv

### Fixed
- Throw 404 error when arke atom is not found by @ilyichv in [#10](https://github.com/arkemishub/arke-server/pull/10)
- Build_filters condition is now called with Parameter instead of id by @ilyichv in [#11](https://github.com/arkemishub/arke-server/pull/11)

### Removed
- Remove configuration in favor of metadata by @ilyichv in [#8](https://github.com/arkemishub/arke-server/pull/8)

## [0.1.3] - 2023-05-19

### Changed
- Set version to 0.1.3 by @ilyichv

## [0.1.2] - 2023-05-19

### Added
- Add github workflow by @ErikFerrari in [#4](https://github.com/arkemishub/arke-server/pull/4)

### Changed
- Set version to 0.1.2 by @ilyichv

### Fixed
- Get unit plug by @ErikFerrari in [#6](https://github.com/arkemishub/arke-server/pull/6)
- Aligned project to new routes by @dorianmercatante in [#3](https://github.com/arkemishub/arke-server/pull/3)

### New Contributors
* @ilyichv made their first contribution
* @ErikFerrari made their first contribution in [#6](https://github.com/arkemishub/arke-server/pull/6)
* @dorianmercatante made their first contribution in [#3](https://github.com/arkemishub/arke-server/pull/3)

[0.4.2]: https://github.com/arkemishub/arke-server/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/arkemishub/arke-server/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/arkemishub/arke-server/compare/v0.3.18...v0.4.0
[0.3.18]: https://github.com/arkemishub/arke-server/compare/v0.3.17...v0.3.18
[0.3.17]: https://github.com/arkemishub/arke-server/compare/v0.3.16...v0.3.17
[0.3.16]: https://github.com/arkemishub/arke-server/compare/v0.3.15...v0.3.16
[0.3.15]: https://github.com/arkemishub/arke-server/compare/v0.3.14...v0.3.15
[0.3.14]: https://github.com/arkemishub/arke-server/compare/v0.3.13...v0.3.14
[0.3.13]: https://github.com/arkemishub/arke-server/compare/v0.3.12...v0.3.13
[0.3.12]: https://github.com/arkemishub/arke-server/compare/v0.3.11...v0.3.12
[0.3.11]: https://github.com/arkemishub/arke-server/compare/v0.3.10...v0.3.11
[0.3.10]: https://github.com/arkemishub/arke-server/compare/v0.3.9...v0.3.10
[0.3.9]: https://github.com/arkemishub/arke-server/compare/v0.3.8...v0.3.9
[0.3.8]: https://github.com/arkemishub/arke-server/compare/v0.3.7...v0.3.8
[0.3.7]: https://github.com/arkemishub/arke-server/compare/v0.3.6...v0.3.7
[0.3.6]: https://github.com/arkemishub/arke-server/compare/v0.3.5...v0.3.6
[0.3.5]: https://github.com/arkemishub/arke-server/compare/v0.3.4...v0.3.5
[0.3.4]: https://github.com/arkemishub/arke-server/compare/v0.3.3...v0.3.4
[0.3.3]: https://github.com/arkemishub/arke-server/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/arkemishub/arke-server/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/arkemishub/arke-server/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/arkemishub/arke-server/compare/v0.1.39...v0.3.0
[0.1.39]: https://github.com/arkemishub/arke-server/compare/v0.1.38...v0.1.39
[0.1.38]: https://github.com/arkemishub/arke-server/compare/v0.1.37...v0.1.38
[0.1.37]: https://github.com/arkemishub/arke-server/compare/v0.1.36...v0.1.37
[0.1.36]: https://github.com/arkemishub/arke-server/compare/v0.1.35...v0.1.36
[0.1.35]: https://github.com/arkemishub/arke-server/compare/v0.1.34...v0.1.35
[0.1.34]: https://github.com/arkemishub/arke-server/compare/v0.1.33...v0.1.34
[0.1.33]: https://github.com/arkemishub/arke-server/compare/v0.1.32...v0.1.33
[0.1.32]: https://github.com/arkemishub/arke-server/compare/v0.1.31...v0.1.32
[0.1.31]: https://github.com/arkemishub/arke-server/compare/v0.1.30...v0.1.31
[0.1.30]: https://github.com/arkemishub/arke-server/compare/v0.1.29...v0.1.30
[0.1.29]: https://github.com/arkemishub/arke-server/compare/v0.1.28...v0.1.29
[0.1.28]: https://github.com/arkemishub/arke-server/compare/v0.1.27...v0.1.28
[0.1.27]: https://github.com/arkemishub/arke-server/compare/v0.1.26...v0.1.27
[0.1.26]: https://github.com/arkemishub/arke-server/compare/v0.1.25...v0.1.26
[0.1.25]: https://github.com/arkemishub/arke-server/compare/v0.1.24...v0.1.25
[0.1.24]: https://github.com/arkemishub/arke-server/compare/v0.1.23...v0.1.24
[0.1.23]: https://github.com/arkemishub/arke-server/compare/v0.1.22...v0.1.23
[0.1.22]: https://github.com/arkemishub/arke-server/compare/v0.1.21...v0.1.22
[0.1.21]: https://github.com/arkemishub/arke-server/compare/v0.1.20...v0.1.21
[0.1.20]: https://github.com/arkemishub/arke-server/compare/v0.1.19...v0.1.20
[0.1.19]: https://github.com/arkemishub/arke-server/compare/v0.1.18...v0.1.19
[0.1.18]: https://github.com/arkemishub/arke-server/compare/v0.1.17...v0.1.18
[0.1.17]: https://github.com/arkemishub/arke-server/compare/v0.1.16...v0.1.17
[0.1.16]: https://github.com/arkemishub/arke-server/compare/v0.1.15...v0.1.16
[0.1.15]: https://github.com/arkemishub/arke-server/compare/v0.1.14...v0.1.15
[0.1.14]: https://github.com/arkemishub/arke-server/compare/v0.1.13...v0.1.14
[0.1.12]: https://github.com/arkemishub/arke-server/compare/v0.1.11...v0.1.12
[0.1.11]: https://github.com/arkemishub/arke-server/compare/v0.1.10...v0.1.11
[0.1.10]: https://github.com/arkemishub/arke-server/compare/v0.1.9...v0.1.10
[0.1.9]: https://github.com/arkemishub/arke-server/compare/v0.1.8...v0.1.9
[0.1.8]: https://github.com/arkemishub/arke-server/compare/v0.1.7...v0.1.8
[0.1.7]: https://github.com/arkemishub/arke-server/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/arkemishub/arke-server/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/arkemishub/arke-server/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/arkemishub/arke-server/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/arkemishub/arke-server/compare/v0.1.2...v0.1.3

<!-- generated by git-cliff -->
