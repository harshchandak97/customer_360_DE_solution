-- Two different birth dates inside one customer means two people were wrongly merged.
select c.customer_id, count(distinct r.date_of_birth) as distinct_dobs
from {{ ref('int_customer_clusters') }} c
join {{ ref('int_customer_records') }} r using (record_key)
where r.date_of_birth is not null
group by c.customer_id
having count(distinct r.date_of_birth) > 1
