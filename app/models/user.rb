class User < ActiveRecord::Base
  has_many :microposts, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :likes, dependent: :destroy
  has_many :authentications, dependent: :destroy
  has_many :topics, dependent: :destroy
  has_many :active_relationships, class_name: "Relationship",
                                  foreign_key: "follower_id",
                                  dependent: :destroy
  has_many :passive_relationships, class_name:  "Relationship",
                                    foreign_key: "followed_id",
                                    dependent: :destroy
  has_many :following, through: :active_relationships, source: :followed
  has_many :followers, through: :passive_relationships, source: :follower

  has_many :topic_relationships, as: 'subject', dependent: :delete_all

  before_save { self.email = email.downcase }
  before_create :create_activation_digest

  validates :name, presence: true, length: { maximum: 50, minimum: 1 }
  VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i
  validates :email, presence: true, length: { maximum: 255 },
                                    format: { with: VALID_EMAIL_REGEX },
                                    uniqueness: { case_sensitive: false }
  # uniqueness: { case_sensitive: false }, 唯一, 不区分大小写
  validates :password, length: { minimum: 6 }, allow_blank: true

  has_secure_password

  # 返回制定字符串的哈希摘要
  def User.digest(string)
    cost = ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST :
                                                  BCrypt::Engine.cost
    BCrypt::Password.create(string, cost: cost)
  end

  # 返回一个随机令牌
  def User.new_token
    SecureRandom.urlsafe_base64
  end

  # 为了持久会话, 在数据库中记住用户
  def remember
    self.remember_token = User.new_token
    update_attribute :remember_token, self.remember_token
    # update_attribute, 这个方法会跳过验证
  end

  # 如果指定的令牌和摘要匹配, 则返回true
  def authenticated?(attribute, attribute_token)
    send("#{attribute}_token") == attribute_token ? true : false
  end

  # 忘记用户
  def forget
    update_attribute :remember_token, nil
  end

  # 激活账户
  def activate
    update_attribute :activated, true
    update_attribute :activated_at, Time.zone.now
  end

  # 发送激活邮件
  def send_activation_email
    UserMailer.account_activation(self).deliver_later
  end

  # 设置密码重设相关的属性
  def create_reset_digest
    self.password_reset_token = User.new_token
    update_attribute :password_reset_token, password_reset_token
    update_attribute :password_reset_email_send_at, Time.zone.now
  end

  # 发送密码重设邮件
  def send_password_reset_email
    UserMailer.password_reset(self).deliver_later
  end

  def password_reset_expired?
    password_reset_email_send_at < 2.hours.ago
    # 应该理解为密码重设邮件发出超过两个小时
  end

  def feed
    following_ids = "SELECT followed_id FROM relationships WHERE follower_id = :user_id"
    Micropost.where("user_id IN (#{following_ids}) OR user_id = :user_id",
                      user_id: id)
  end

  # 关注另一个用户
  def follow(other_user)
    active_relationships.create(followed_id: other_user.id)
  end

  # 取消关注另一个用户
  def unfollow(other_user)
    active_relationships.find_by(followed_id: other_user.id).destroy
  end

  # 如果当前用户关注了指定用户，返回true
  def following?(other_user)
    following.include?(other_user)
  end

  # 如果当前用户是管理员，返回true
  def admin?
    CONFIG['admin_emails'] && CONFIG['admin_emails'].include?(email)
  end

  def User.find_or_create_from_auth_hash(user_params)
    find_by(email: user_params[:email]) || create(user_params)
  end

  private
    # 创建并赋值激活令牌和摘要
    def create_activation_digest
      self.activation_token = User.new_token
    end
end
