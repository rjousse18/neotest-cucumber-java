Feature: Shipment loading

  Scenario: Plain scenario
    Given something
    Then it works

  Scenario Outline: Validation <use_case>
    Given the data in "<BASE>"
    Then the result is <result>
    Examples:
      | use_case          | BASE | result |
      | 01 - happy path   | a/01 | ok     |
      | 02 - empty input  | a/02 | ko     |

  Scenario Outline: Same title for every row
    Given the data in "<BASE>"
    Examples:
      | Use Case | BASE |
      | MVP      | b/01 |
      | Edge     | b/02 |
