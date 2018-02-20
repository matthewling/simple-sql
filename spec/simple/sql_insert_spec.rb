require "spec_helper"

describe "Simple::SQL.insert" do
  let!(:users) { 1.upto(USER_COUNT).map { create(:user) } }

  it "inserts a single user" do
    initial_ids = SQL.all("SELECT id FROM users")

    id = SQL.insert :users, first_name: "foo", last_name: "bar"
    expect(id).to be_a(Integer)
    expect(initial_ids).not_to include(id)
    expect(SQL.ask("SELECT count(*) FROM users")).to eq(USER_COUNT+1)

    user = SQL.record("SELECT * FROM users WHERE id=$1", id, into: OpenStruct)
    expect(user.first_name).to eq("foo")
    expect(user.last_name).to eq("bar")
    expect(user.created_at).to be_a(Time)
  end
end

