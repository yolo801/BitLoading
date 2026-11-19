function index = dmt_vm_three_order_select(swingCode,isValidated,orderCounts,minPerOrder)
%DMT_VM_THREE_ORDER_SELECT Choose the nearest eligible integer centi-swing.
assert(iscolumn(swingCode) && all(swingCode==fix(swingCode)) && ...
    numel(unique(swingCode))==numel(swingCode) && isequal(size(swingCode),size(isValidated)) && ...
    size(orderCounts,1)==numel(swingCode) && size(orderCounts,2)==3);
eligible=find(isValidated & all(orderCounts>=minPerOrder,2));
index=[];
if ~isempty(eligible)
    % Comparing integer distances to 62.5 avoids floating-point tie errors.
    codes=swingCode(eligible);
    [~,order]=sortrows([abs(2*codes-125) codes],[1 2]);
    index=eligible(order(1));
end
end
