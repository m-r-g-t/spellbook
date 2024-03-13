{{
  config(
    schema = 'lending_optimism',
    alias = 'base_flashloans',
    materialized = 'view'
  )
}}

{%
  set models = [
    ref('aave_v3_optimism_base_flashloans'),
    ref('granary_optimism_base_flashloans')
  ]
%}

{% for model in models %}
select
  blockchain,
  project,
  version,
  recipient,
  amount,
  fee,
  token_address,
  contract_address,
  block_month,
  block_time,
  block_number,
  tx_hash,
  evt_index
from {{ model }}
{% if not loop.last %}
union all
{% endif %}
{% endfor %}
