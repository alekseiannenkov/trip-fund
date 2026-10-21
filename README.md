# TripFund — сбор на поездку команды (Solidity, Foundry)

Контракт `TripFund` собирает взносы в одном ERC-20 до дедлайна. После дедлайна:

- если `totalRaised >= goal` — организатор **один раз** забирает всю учтённую сумму через `withdraw()`;
- иначе каждый участник забирает **свой полный вклад** через `refund()`.

Бонус V1: `TripFundV1` — та же логика, но за `TransparentUpgradeableProxy` (OpenZeppelin 5.x)
с параметрами в storage и инициализацией через `initialize`.

## Версии

| Компонент | Версия |
|---|---|
| Foundry (forge / cast / anvil) | 1.5.1-stable |
| Solidity (solc) | 0.8.28 (EVM `cancun`) |
| OpenZeppelin Contracts | v5.4.0 |
| forge-std | v1.17.0 |

## Структура

```
src/
  TripFund.sol              основной контракт (immutable-параметры, без сеттеров)
  TripFundV1.sol            бонус: обновляемая версия для Transparent Proxy
  mocks/MockToken.sol       ERC-20 на OpenZeppelin без комиссий и rebasing + mint
test/
  TripFund.t.sol            пункты 1–9: взносы, дедлайн, вывод, возвраты, прямые переводы
  TripFundTransferFailure.t.sol  п. 5: ошибка перевода откатывает всю операцию
  TripFundProxy.t.sol       бонус п. 10: прокси, initialize, запрет переинициализации, upgrade
  mocks/FailingToken.sol    токен, у которого transfer может вернуть false
script/
  DeployTripFund.s.sol      деплой MockToken + TripFund
  DeployTripFundProxy.s.sol деплой MockToken + TripFundV1 + прокси
foundry.toml
```

## Установка

Нужен Foundry: https://book.getfoundry.sh/getting-started/installation

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Клонирование с зависимостями (они подключены как git-сабмодули в `lib/`):

```bash
git clone --recurse-submodules https://github.com/alekseiannenkov/trip-fund trip-fund
cd trip-fund
# если клонировали без --recurse-submodules:
git submodule update --init --recursive
```

Если собираете проект с нуля из этих файлов:

```bash
git init
forge install foundry-rs/forge-std@v1.17.0 OpenZeppelin/openzeppelin-contracts@v5.4.0
```

## Сборка и тесты

```bash
forge build
forge test          # 39 тестов
forge test -vvv     # с трассировкой упавших тестов
forge test --match-contract TripFundProxyTest   # только бонус
```

## Пример: approve + взнос (локально, anvil)

Терминал 1:

```bash
anvil
```

Терминал 2 (ключ — первый тестовый аккаунт anvil, он же деплоер, организатор и владелец 1000 TRIP):

```bash
export RPC=http://127.0.0.1:8545
export PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export ME=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

forge script script/DeployTripFund.s.sol --rpc-url $RPC --private-key $PK --broadcast
# в логе будут адреса MockToken и TripFund — подставьте их:
export TOKEN=<адрес MockToken>
export FUND=<адрес TripFund>

# 1) разрешить TripFund списать 50 TRIP
cast send $TOKEN "approve(address,uint256)" $FUND 50ether --rpc-url $RPC --private-key $PK
# 2) внести 50 TRIP
cast send $FUND "contribute(uint256)" 50ether --rpc-url $RPC --private-key $PK

# проверить учёт
cast call $FUND "contributions(address)(uint256)" $ME --rpc-url $RPC   # 50000000000000000000
cast call $FUND "totalRaised()(uint256)" --rpc-url $RPC                # 50000000000000000000
cast call $TOKEN "balanceOf(address)(uint256)" $FUND --rpc-url $RPC    # 50000000000000000000
```

Параметры деплоя можно задать переменными окружения: `ORGANIZER`, `GOAL` (в минимальных единицах),
`DURATION` (секунды до дедлайна), например `GOAL=200000000000000000000 DURATION=3600 forge script ...`.

То же самое в Solidity (как в тестах):

```solidity
token.approve(address(fund), 50 ether);
fund.contribute(50 ether);
```

Бонус через прокси — `approve` делается на **адрес прокси**:

```bash
forge script script/DeployTripFundProxy.s.sol --rpc-url $RPC --private-key $PK --broadcast
export FUND=<адрес Proxy (TripFund)>
cast send $TOKEN "approve(address,uint256)" $FUND 50ether --rpc-url $RPC --private-key $PK
cast send $FUND "contribute(uint256)" 50ether --rpc-url $RPC --private-key $PK
```

## Интерфейс TripFund

| Функция / поле | Описание |
|---|---|
| `token()`, `organizer()`, `goal()`, `deadline()` | параметры, задаются один раз, изменить нельзя |
| `contribute(uint256 amount)` | `amount > 0`, `block.timestamp < deadline`, списание через `safeTransferFrom` |
| `withdraw()` | только организатор, `block.timestamp >= deadline`, `totalRaised >= goal`, один раз |
| `refund()` | `block.timestamp >= deadline`, `totalRaised < goal`, вклад > 0 |
| `contributions(address)` | текущий невозвращённый вклад |
| `totalRaised()` | сумма всех принятых взносов, после выплат не уменьшается |
| `withdrawn()` | была ли выплата организатору |
| события | `Contributed(contributor, amount)`, `Refunded(contributor, amount)`, `Withdrawn(organizer, amount)` |

Ошибки — кастомные: `ZeroAddress`, `ZeroGoal`, `DeadlineNotInFuture`, `ZeroAmount`, `DeadlinePassed`,
`DeadlineNotReached`, `NotOrganizer`, `GoalNotReached`, `GoalReached`, `AlreadyWithdrawn`, `NothingToRefund`.

## Как выполнены требования

**Реализация**

1. Параметры — `immutable`, проверки в конструкторе (нулевые адреса, нулевая цель, `deadline <= now`). Сеттеров нет.
2. `contribute` — `safeTransferFrom(msg.sender, this, amount)`, повторные взносы суммируются.
3. `contributions` и `totalRaised` — публичные. Учитываются только взносы через `contribute`; прямые переводы
   на баланс контракта нигде не используются: организатор получает ровно `totalRaised`, возвраты — ровно вклад.
4. Исход определяется только после дедлайна сравнением `totalRaised` с `goal`.
5. Выплаты через `safeTransfer`; порядок checks → effects → interactions: вклад обнуляется, флаг `withdrawn`
   ставится **до** перевода. Ошибка перевода откатывает всю транзакцию (проверено в `TripFundTransferFailure.t.sol`).

**Тесты** (`test/TripFund.t.sol`)

| Пункт | Тесты |
|---|---|
| 6 | `test_TwoContributorsAndRepeatedContributions`, `test_Contribute_RevertZeroAmount`, `..._RevertInsufficientBalance`, `..._RevertInsufficientAllowance`, `..._RevertWithoutApprove` — после отката сравнивается снимок учёта и балансов |
| 7 | `test_Contribute_OneSecondBeforeDeadline`, `test_Contribute_RevertExactlyAtDeadline`, `test_Withdraw_RevertBeforeDeadline_EvenIfGoalReached`, `test_Refund_RevertBeforeDeadline` |
| 8 | `test_Withdraw_ExactlyGoal`, `test_Withdraw_AboveGoal`, `test_Refund_BelowGoal_Independent`, `test_Withdraw_RevertNotOrganizer`, `test_Withdraw_RevertTwice`, `test_Refund_RevertTwice`, `test_Refund_RevertOnSuccess`, `test_Withdraw_RevertOnFailure`, `test_Refund_RevertWithoutContribution` |
| 9 | `test_DirectTransfer_NotCounted_Success`, `test_DirectTransfer_NotCounted_Failure` (прямой перевод не «спасает» провалившийся сбор и остаётся в контракте) |

**Бонус V1, п. 10** (`src/TripFundV1.sol`, `test/TripFundProxy.t.sol`)

- `TripFundV1 is Initializable`, параметры в storage, задаются в `initialize(token, organizer, goal, deadline)`,
  которая вызывается в конструкторе `TransparentUpgradeableProxy` (тот же набор проверок).
- В конструкторе реализации `_disableInitializers()` — прямая инициализация реализации запрещена
  (`test_Implementation_RevertDirectInitialize`).
- Модификатор `initializer` запрещает повторную инициализацию прокси (`test_Proxy_RevertReinitialize`).
- В OZ 5.x прокси сам создаёт `ProxyAdmin`, владельцем которого становится переданный `initialOwner`.
  Обновлять может только он: `test_Upgrade_RevertNotProxyAdminOwner`, `test_Upgrade_ByOwner_KeepsState`
  (адрес, параметры, вклады, `totalRaised` и токенный баланс сохраняются).
- Порядок storage-переменных зафиксирован комментариями; новые переменные в V2 добавляются только в конец.
