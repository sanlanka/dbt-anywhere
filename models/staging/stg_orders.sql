with source as (

    select * from {{ ref('raw_orders') }}

)

select
    order_id,
    customer_id,
    cast(order_date as date)   as order_date,
    cast(amount as decimal(10, 2)) as amount,
    status

from source
