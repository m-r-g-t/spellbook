{{ config
(
    tags = ['legacy'],
    schema = 'kyberswap_aggregator_optimism',
    alias = alias('trades', legacy_model=True)
)
}}

-- DUMMY TABLE, WILL BE REMOVED SOON
SELECT 1
